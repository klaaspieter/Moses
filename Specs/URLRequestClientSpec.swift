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
            expect{self.session.request.HTTPBody}.toEventually(equal("key1=value1&key2=value2".dataUsingEncoding(NSUTF8StringEncoding)))
        }
    }
}
