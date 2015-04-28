import Quick
import Nimble

import Moses

class MockDataTask : NSURLSessionDataTask {
    var resumed: Bool = false

    override func resume() {
        resumed = true
    }
}

class MockURLSession : NSURLSession {
    var request: NSURLRequest!
    var completionHandler: ((NSData!, NSURLResponse!, NSError!) -> Void)!

    var dataTask = MockDataTask()

    override func dataTaskWithRequest(request: NSURLRequest, completionHandler: ((NSData!, NSURLResponse!, NSError!) -> Void)?) -> NSURLSessionDataTask {
        self.request = request
        self.completionHandler = completionHandler
        return dataTask
    }
}

func stringFromData(data: NSData) -> NSString? {
    return NSString(data: data, encoding: NSUTF8StringEncoding)
}

class URLRequestClientSpec : QuickSpec {
    var session: MockURLSession! = nil
    var client: URLRequestClient! = nil

    override func spec() {
        beforeEach {
            self.session = MockURLSession()
            self.client = URLRequestClient(session: self.session)
        }

        it("asks the session for a POST request data task") {
            self.client.post("http://fake", parameters: [:]) { data, response, error in }
            expect{self.session.request.HTTPMethod}.toEventually(equal("POST"))
        }

        it("resumes the data task") {
            self.client.post("http://fake", parameters: [:]) { data, response, error in }
            expect{self.session.dataTask.resumed}.toEventually(beTrue())
        }

        it("gets a POST request task with encoded parameters") {
            let parameters = ["key1": "value1", "key2": "value2"]
            self.client.post("http://fake", parameters: parameters) { data, response, error in }
            expect{stringFromData(self.session.request.HTTPBody!)}.toEventually(equal("key1=value1&key2=value2"))
        }

        it("url encodes parameters") {
            let randomPassword = ""
            self.client.post("http://fake", parameters: ["k^e y": "v+ /a&l^u!e"]) { data, response, error in }
            expect(stringFromData(self.session.request.HTTPBody!)).toEventually(equal("k%5Ee%20y=v%2B%20/a%26l%5Eu%21e"))
        }
    }
}
