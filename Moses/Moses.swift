import Foundation

// Copied from Alamofire
// https://github.com/Alamofire/Alamofire/blob/66fde65b6eddc81933364ca2a734bfe37e1457e7/Source/Alamofire.swift#L165
public protocol URLStringConvertible {
    var URLString: String { get }
}

extension String: URLStringConvertible {
    public var URLString: String {
        return self
    }
}

extension NSURL: URLStringConvertible {
    public var URLString: String {
        return absoluteString!
    }
}

extension NSURLComponents: URLStringConvertible {
    public var URLString: String {
        return URL!.URLString
    }
}

extension NSURLRequest: URLStringConvertible {
    public var URLString: String {
        return URL!.URLString
    }
}

public let MosesErrorDomain = "me.annema.moses_error_domain"
public let MosesErrorUriKey = "MosesErrorURIKey"

public enum MosesError: Int {
    case InvalidResponse
}

public enum OAuth2Error: Int {
    case InvalidRequest
    case InvalidClient
    case InvalidGrant
    case UnauthorizedClient
    case UnsupportedGrantType
    case InvalidScope
    case Unknown

    static func create(#statusCode: String) -> OAuth2Error {
        switch statusCode {
        case "invalid_request":
            return .InvalidRequest

        case "invalid_client":
            return .InvalidClient

        case "invalid_grant":
            return .InvalidGrant

        case "unauthorized_client":
            return .UnauthorizedClient

        case "unsupported_grant_type":
            return .UnsupportedGrantType

        case "invalid_scope":
            return .InvalidScope

        default:
            return .Unknown
        }
    }
}

public protocol OAuth2Request {
    var url: URLStringConvertible { get }
    var parameters: [String: String] { get }

    func success(closure: ((OAuthCredential) -> Void)) -> Self
    func failure(closure: ((NSError) -> Void)) -> Self
}

public class Request : OAuth2Request {
    public let url: URLStringConvertible
    public let parameters: [String: String]

    private let queue: dispatch_queue_t

    private var credential: OAuthCredential? = nil
    private var error: NSError? = nil

    private var isResolved: Bool { return credential != nil || error != nil }

    public init(url: URLStringConvertible, parameters: [String: String], resolver: (((OAuthCredential) -> Void), ((NSError) -> Void)) -> Void) {
        self.url = url
        self.parameters = parameters

        queue = {
            let label: String = "me.annema.task-oauth"
            let queue = dispatch_queue_create((label as NSString).UTF8String, DISPATCH_QUEUE_SERIAL)

            dispatch_suspend(queue)

            return queue
            }()

        dispatch_async(dispatch_get_main_queue()) {
            resolver({ (credential) in self.succeed(credential) }, { (error) in self.fail(error) } )
        }
    }

    deinit {
        if !isResolved {
            dispatch_resume(queue)
        }
    }

    public func success(closure: ((OAuthCredential) -> Void)) -> Self {
        dispatch_async(queue) {
            if let credential = self.credential {
                dispatch_async(dispatch_get_main_queue()) { closure(credential) }
            }
        }
        return self
    }

    private func raiseIfResolved() {
        if isResolved {
            NSException(name: NSInternalInconsistencyException, reason: "A Request cannot be resolved more than once.", userInfo: nil).raise()
        }
    }

    private func succeed(credential: OAuthCredential) {
        raiseIfResolved()
        self.credential = credential
        dispatch_resume(queue)
    }

    public func failure(closure: ((NSError) -> Void)) -> Self {
        dispatch_async(queue) {
            if let error = self.error {
                dispatch_async(dispatch_get_main_queue()) { closure(error) }
            }
        }
        return self
    }

    private func fail(error: NSError) {
        raiseIfResolved()
        self.error = error
        dispatch_resume(queue)
    }
}

public protocol HTTPClient {
    func post(url: URLStringConvertible, parameters: [String: String], completionHandler: (NSData!, NSURLResponse!, NSError!) -> Void)
}

public class URLRequestClient : HTTPClient {
    var session: NSURLSession = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration())

    public init() {}
    public init(session: NSURLSession) {
        self.session = session
    }

    public func post(url: URLStringConvertible, parameters: [String: String], completionHandler: (NSData!, NSURLResponse!, NSError!) -> Void) {
        self.session.dataTaskWithRequest(self.buildRequest(url, parameters: parameters), completionHandler: completionHandler).resume()
    }

    func buildRequest(url: URLStringConvertible, parameters: [String: String]) -> NSURLRequest {
        let request = NSMutableURLRequest(URL: NSURL(string: url.URLString)!)
        request.HTTPMethod = "POST"
        request.HTTPBody = join("&", map(parameters) { (key, value) in "\(self.encode(key, value))" }).dataUsingEncoding(NSUTF8StringEncoding)
        return request
    }

    func encode(key: String, _ value: String) -> String {
        return "\(self.escape(key))=\(self.escape(value))"
    }

    // Taken from Alamofire
    func escape(string: String) -> String {
        let legalURLCharactersToBeEscaped: CFStringRef = ":&=;+!@#$()',*"
        return CFURLCreateStringByAddingPercentEscapes(nil, string, nil, legalURLCharactersToBeEscaped, CFStringBuiltInEncodings.UTF8.rawValue) as String
    }
}

public struct OAuthCredential {
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String
    public let expiration: NSDate?

    public init(accessToken: String, refreshToken: String?, tokenType: String, expiration: NSDate?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiration = expiration
    }
}

extension OAuthCredential : Printable {
    public var description: String {
        return "<OAuthCredential accessToken: \"\(accessToken)\" tokenType: \"\(tokenType)\" refreshToken: \"\(refreshToken)\" expiration: \"\(expiration)\">"
    }
}

final class Box<T> {
    let unbox: T
    init(_ value: T) { self.unbox = value }
}

enum Result<T,E> {
    case Success(Box<T>)
    case Failure(Box<E>)
}

extension OAuthCredential : Equatable {}
public func ==(lhs: OAuthCredential, rhs: OAuthCredential) -> Bool {
    var equal = false
    if let le = lhs.expiration {
        if let re = rhs.expiration {
            equal = le.timeIntervalSinceDate(re) <= 0.1
        }
    }
    return lhs.accessToken == rhs.accessToken
        && lhs.refreshToken == rhs.refreshToken
        && lhs.tokenType == rhs.tokenType
        && equal
}


public struct OAuth2Client {
    public let endpoint: URLStringConvertible
    public let httpClient: HTTPClient
    public let clientID: String

    public init(_ endpoint: URLStringConvertible, clientID: String) {
        self.init(endpoint, clientID: clientID, httpClient: URLRequestClient())
    }

    public init(_ endpoint: URLStringConvertible, clientID: String, httpClient: HTTPClient) {
        self.endpoint = endpoint
        self.httpClient = httpClient
        self.clientID = clientID
    }

    func buildParameters(username: String, _ password: String) -> [String:String] {
        return ["client_id": clientID, "grant_type": "password", "username": username, "password": password]
    }

    func buildToken(body: NSDictionary) -> Result<OAuthCredential, NSError> {
        let missingKeys = ["access_token", "token_type"].filter { !contains(body.allKeys as! [String], $0) }

        if missingKeys.count > 0 {
            let failureReason = "Required key(s) missing: \(missingKeys)"
            let error = NSError(domain: MosesErrorDomain, code: MosesError.InvalidResponse.rawValue, userInfo: [
                NSLocalizedFailureReasonErrorKey: failureReason,
                NSLocalizedDescriptionKey: "The server responded with an invalid access token"
            ])
            return Result.Failure(Box(error))
        }

        let accessToken = body["access_token"] as! String
        let refreshToken = body["refresh_token"] as? String
        let tokenType = body["token_type"] as! String

        var expiration: NSDate? = nil
        if let expiresIn = body["expires_in"] as? NSTimeInterval {
            expiration = NSDate(timeIntervalSinceNow: expiresIn)
        }
        let credential = OAuthCredential(accessToken: accessToken,
            refreshToken: refreshToken, tokenType: tokenType, expiration: expiration)
        return Result.Success(Box(credential))
    }

    func buildError(body: NSDictionary) -> NSError {
        let errorCode = OAuth2Error.create(statusCode: body["error"] as! String)

        var userInfo: [NSObject: AnyObject] = [:]
        if let description: AnyObject? = body["error_description"] {
            userInfo[NSLocalizedDescriptionKey] = description
        }
        if let uri: AnyObject? = body["error_uri"] {
            userInfo[MosesErrorUriKey] = uri
        }

        return NSError(domain: MosesErrorDomain, code: errorCode.rawValue, userInfo: userInfo)
    }

    public func authorize(username: String, _ password: String) -> OAuth2Request {
        let parameters = buildParameters(username, password)
        return Request(url: self.endpoint, parameters: parameters) { (succeed: (OAuthCredential) -> Void, fail: (NSError) -> Void) in
            self.httpClient.post(self.endpoint, parameters: parameters) { data, response, error in
                if let error = error {
                    return fail(error)
                }

                let httpResponse = response as! NSHTTPURLResponse
                if contains(200..<300, httpResponse.statusCode) || contains(400..<500, httpResponse.statusCode) {
                    let body = NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.allZeros, error: nil) as! NSDictionary
                    if let error: AnyObject = body["error"] {
                        fail(self.buildError(body))
                    } else {
                        switch self.buildToken(body) {
                        case let .Failure(error):
                            fail(error.unbox)

                        case let .Success(token):
                            succeed(token.unbox)
                        }
                    }
                } else {
                    var userInfo = [NSLocalizedDescriptionKey: "Expected status code in (200-299) or (400-499) got \(httpResponse.statusCode)"]
                    if let suggestion = NSString(data: data, encoding: NSUTF8StringEncoding) {
                        userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion as String
                    }

                    fail(NSError(domain: MosesErrorDomain, code: MosesError.InvalidResponse.rawValue, userInfo: userInfo))
                }
            }
        }
    }

    public func reauthorize(refreshToken: String) -> OAuth2Request {
        let parameters = [
            "refresh_token": refreshToken,
            "client_id": self.clientID,
            "grant_type": "refresh_token"
        ]
        return Request(url: self.endpoint, parameters: parameters, resolver: { credential, error in
        })
    }
}
