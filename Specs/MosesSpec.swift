import Quick
import Nimble

import Moses

class FakeHTTPClient : HTTPClient {
    var requests: [String] = []
    var completionHandler: ((NSData!, NSURLResponse!, NSError!) -> Void)!

    func post(url: URLStringConvertible, parameters: [String: String], completionHandler: (NSData!, NSURLResponse!, NSError!) -> Void) {
        self.requests.append(url.URLString)
        self.completionHandler = completionHandler
    }
}

// This is a workaround for a compiler bug. Doing this in a beforeEach block
// fails to compile for some reason.
func makeRequest(client: OAuth2Client, httpClient: FakeHTTPClient) -> OAuth2Request {
    let request = client.authorize("test", "test")
    waitUntil { done in
        if httpClient.completionHandler != nil {
            done()
        }
    }
    return request
}

func json(object: AnyObject) -> NSData {
    return NSJSONSerialization.dataWithJSONObject(object, options: NSJSONWritingOptions.allZeros, error: nil)!
}

class MosesSpec : QuickSpec {
    override func spec() {
        var client: OAuth2Client! = nil
        var httpClient: FakeHTTPClient! = nil

        beforeEach {
            httpClient = FakeHTTPClient()
            client = OAuth2Client("http://endpoint", clientID: "client_id", httpClient: httpClient)
        }

        it("requires an endpoint and client id") {
            let endpoint = NSURL(string: "http://annema.me/oauth2/token")!
            let clientID = "clientID"
            let client = OAuth2Client(endpoint, clientID: clientID)
            expect(client.endpoint.URLString) == endpoint.URLString
            expect(client.clientID) == clientID
        }

        it("accepts strings as endpoint") {
            let endpoint = "http://annema.me/oauth2/token"
            let client = OAuth2Client(endpoint, clientID: "id")
            expect(client.endpoint.URLString) == endpoint
        }

        it("can be initialized with a HTTP client") {
            let httpClient = FakeHTTPClient()
            let client = OAuth2Client("http://endpoint/oauth2/token", clientID: "id", httpClient: httpClient)
            expect(client.httpClient).toNot(beNil())
        }

        describe("#authorize") {
            let endpoint = "http://endpoint/oauth2/token"
            let httpClient = FakeHTTPClient()
            let clientID = "client_id"
            let client = OAuth2Client("http://endpoint/oauth2/token", clientID: clientID, httpClient: httpClient)
            let username = "klaaspieter@annema.me"
            let password = "password"

            it("makes a request to the endpoint") {
                client.authorize(username, password)
                expect(httpClient.requests).toEventually(equal([endpoint]))
            }

            it("provides the username as a parameter") {
                let parameters = client.authorize(username, password).parameters
                expect(parameters["username"]) == username
            }

            it("provides the password as a parameter") {
                let parameters = client.authorize(username, password).parameters
                expect(parameters["password"]) == password
            }

            it("provides the client id as a parameter") {
                let parameters = client.authorize(username, password).parameters
                expect(parameters["client_id"]) == clientID
            }

            it("provides the password grant type as a parameter") {
                let parameters = client.authorize(username, password).parameters
                expect(parameters["grant_type"]) == "password"
            }

            context("failure") {
                context("no http response") {
                    it("provides the error") {
                        let request = makeRequest(client, httpClient)

                        let error = NSError()
                        httpClient.completionHandler(nil, nil, error)

                        var called = false
                        request.failure {
                            expect($0) === error
                            called = true
                        }
                        expect{called}.toEventually(beTrue())
                    }
                }

                context("response with code 5xx") {
                    it("provides the error") {
                        let request = makeRequest(client, httpClient)

                        let response = NSHTTPURLResponse(URL: NSURL(string: client.endpoint.URLString)!,
                            statusCode: 500, HTTPVersion: nil, headerFields: nil)
                        httpClient.completionHandler("response body".dataUsingEncoding(NSUTF8StringEncoding), response, nil)

                        var error: NSError?
                        request.failure { error = $0 }

                        expect{error}.toEventuallyNot(beNil())
                        expect(error?.domain) == MosesErrorDomain
                        expect(error?.code) == MosesError.InvalidResponse.rawValue
                        expect(error?.localizedRecoverySuggestion) == "response body"
                    }
                }

                describe("response body") {
                    var response: NSHTTPURLResponse! = nil

                    beforeEach {
                        response = NSHTTPURLResponse(URL: NSURL(string: client.endpoint.URLString)!,
                            statusCode: 400, HTTPVersion: nil, headerFields: nil)
                    }

                    it("must have an access token") {
                        let request = makeRequest(client, httpClient)

                        let body = json(["refresh_token": "refresh_token", "token_type": "token_type", "expires_in": 3600])
                        httpClient.completionHandler(body, response, nil)

                        var error: NSError? = nil
                        request.failure { error = $0 }

                        expect{error}.toEventuallyNot(beNil())
                        expect(error?.domain) == MosesErrorDomain
                        expect(error?.code) == MosesError.InvalidResponse.rawValue
                        expect(error?.localizedFailureReason).to(contain("access_token"))
                    }

                    it("must have a token type") {
                        let request = makeRequest(client, httpClient)

                        let body = json(["access_token": "access_token", "refresh_token": "refresh_token", "expires_in": 3600])
                        httpClient.completionHandler(body, response, nil)

                        var error: NSError? = nil
                        request.failure { error = $0 }

                        expect{error}.toEventuallyNot(beNil())
                        expect(error?.domain) == MosesErrorDomain
                        expect(error?.code) == MosesError.InvalidResponse.rawValue
                        expect(error?.localizedFailureReason).to(contain("token_type"))
                    }

                    it("correctly reports multiple missing keys") {
                        let request = makeRequest(client, httpClient)

                        let body = json(["refresh_token": "refresh_token", "expires_in": "expires_in"])
                        httpClient.completionHandler(body, response, nil)

                        var error: NSError? = nil
                        request.failure { error = $0 }

                        expect{error}.toEventuallyNot(beNil())
                        expect(error?.domain) == MosesErrorDomain
                        expect(error?.code) == MosesError.InvalidResponse.rawValue
                        expect(error?.localizedFailureReason).to(contain("access_token"))
                        expect(error?.localizedFailureReason).to(contain("token_type"))
                    }

                    context("error") {
                        it("understands `invalid_request` errors") {
                            let request = makeRequest(client, httpClient)

                            let body = json(["error": "invalid_request"])
                            httpClient.completionHandler(body, response, nil)

                            var error: NSError? = nil
                            request.failure { error = $0 }

                            expect{error}.toEventuallyNot(beNil())
                            expect(error?.domain) == MosesErrorDomain
                            expect(error?.code) == OAuth2Error.InvalidRequest.rawValue
                        }

                        it("understands 'invalid_client' errors") {
                            let request = makeRequest(client, httpClient)

                            let body = json(["error": "invalid_client"])
                            httpClient.completionHandler(body, response, nil)

                            var error: NSError? = nil
                            request.failure { error = $0 }

                            expect{error}.toEventuallyNot(beNil())
                            expect(error?.domain) == MosesErrorDomain
                            expect(error?.code) == OAuth2Error.InvalidClient.rawValue
                        }

                        it("understands 'invalid_grant' errors") {
                            let request = makeRequest(client, httpClient)

                            let body = json(["error": "invalid_grant"])
                            httpClient.completionHandler(body, response, nil)

                            var error: NSError? = nil
                            request.failure { error = $0 }

                            expect{error}.toEventuallyNot(beNil())
                            expect(error?.domain) == MosesErrorDomain
                            expect(error?.code) == OAuth2Error.InvalidGrant.rawValue
                        }

                        it("understands 'unauthorized_client' errors") {
                            let request = makeRequest(client, httpClient)

                            let body = json(["error": "unauthorized_client"])
                            httpClient.completionHandler(body, response, nil)

                            var error: NSError? = nil
                            request.failure { error = $0 }

                            expect{error}.toEventuallyNot(beNil())
                            expect(error?.domain) == MosesErrorDomain
                            expect(error?.code) == OAuth2Error.UnauthorizedClient.rawValue
                        }

                        it("understands 'unsupported_grant_type' errors") {
                            let request = makeRequest(client, httpClient)

                            let body = json(["error": "unsupported_grant_type"])
                            httpClient.completionHandler(body, response, nil)

                            var error: NSError? = nil
                            request.failure { error = $0 }

                            expect{error}.toEventuallyNot(beNil())
                            expect(error?.domain) == MosesErrorDomain
                            expect(error?.code) == OAuth2Error.UnsupportedGrantType.rawValue
                        }

                        it("understands 'invalid_scope' errors") {
                            let request = makeRequest(client, httpClient)

                            let body = json(["error": "invalid_scope"])
                            httpClient.completionHandler(body, response, nil)

                            var error: NSError? = nil
                            request.failure { error = $0 }

                            expect{error}.toEventuallyNot(beNil())
                            expect(error?.domain) == MosesErrorDomain
                            expect(error?.code) == OAuth2Error.InvalidScope.rawValue
                        }

                        it("can optionally have a error_description") {
                            let request = makeRequest(client, httpClient)

                            let body = json(["error": "invalid_request", "error_description": "description"])
                            httpClient.completionHandler(body, response, nil)

                            var error: NSError? = nil
                            request.failure { error = $0 }

                            expect{error}.toEventuallyNot(beNil())
                            expect(error?.localizedDescription) == "description"
                        }

                        it("can optionally have a error_uri") {
                            let request = makeRequest(client, httpClient)

                            let body = json(["error": "invalid_request", "error_uri": "error_uri"])
                            httpClient.completionHandler(body, response, nil)

                            var error: NSError? = nil
                            request.failure { error = $0 }

                            expect{error}.toEventuallyNot(beNil())
                            expect(error?.userInfo?[MosesErrorUriKey] as! String?) == "error_uri"
                        }
                    }
                }
            }

            context("success") {
                var response: NSHTTPURLResponse? = nil

                beforeEach {
                    response = NSHTTPURLResponse(URL: NSURL(string: client.endpoint.URLString)!,
                        statusCode: 200, HTTPVersion: nil, headerFields: nil)
                }

                it("provides the oauth token to the success closure") {
                    let request = makeRequest(client, httpClient)

                    var credential: OAuthCredential? = nil
                    request.success { credential = $0 }

                    let body = json(["access_token": "access_token", "refresh_token": "refresh_token", "token_type": "token_type", "expires_in": 3600])
                    httpClient.completionHandler(body, response, nil)

                    expect{credential}.toEventuallyNot(beNil())
                    expect(credential?.accessToken) == "access_token"
                    expect(credential?.refreshToken) == "refresh_token"
                    expect(credential?.tokenType) == "token_type"
                    expect(credential?.expiration?.timeIntervalSinceNow) ≈ 3600 ± 1
                }

                describe("the body") {
                    it("doesn't need a refresh token") {
                        let request = makeRequest(client, httpClient)

                        let body = json(["access_token": "access_token", "token_type": "token_type", "expires_in": 3600])
                        httpClient.completionHandler(body, response, nil)

                        var credential: OAuthCredential? = nil
                        request.success { credential = $0 }

                        expect{credential}.toEventuallyNot(beNil())
                        expect(credential?.accessToken) == "access_token"
                        expect(credential?.tokenType) == "token_type"
                        expect(credential?.expiration?.timeIntervalSinceNow) ≈ 3600 ± 1
                    }

                    it("doesn't need an expiry time") {
                        let request = makeRequest(client, httpClient)

                        let body = json(["access_token": "access_token", "token_type": "token_type", "refresh_token": "refresh_token"])
                        httpClient.completionHandler(body, response, nil)

                        var credential: OAuthCredential? = nil
                        request.success { credential = $0 }

                        expect{credential}.toEventuallyNot(beNil())
                        expect(credential?.accessToken) == "access_token"
                        expect(credential?.refreshToken) == "refresh_token"
                        expect(credential?.tokenType) == "token_type"
                    }
                }
            }
        }

        describe("#reauthorize") {
            let endpoint = "http://endpoint/oauth2/token"
            let httpClient = FakeHTTPClient()
            let clientID = "client_id"
            let client = OAuth2Client("http://endpoint/oauth2/token", clientID: clientID, httpClient: httpClient)
            let token = "refresh_token"

            it("makes a request to the endpoint") {
                client.reauthorize(token)
                expect(httpClient.requests).toEventually(equal([endpoint]))
            }

            it("provides the refresh token as a parameter") {
                let parameters = client.reauthorize(token).parameters
                expect(parameters["refresh_token"]) == token
            }

            it("provides the client id as a parameter") {
                let parameters = client.reauthorize(token).parameters
                expect(parameters["client_id"]) == clientID
            }

            it("provides the refresh_token grant type as a parameter") {
                let parameters = client.reauthorize(token).parameters
                expect(parameters["grant_type"]) == "refresh_token"
            }
        }
    }
}