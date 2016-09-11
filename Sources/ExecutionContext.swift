//
//  Copyright (c) 2016 Anton Mironov
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom
//  the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
//  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

import Dispatch

public protocol ExecutionContext : class {
  var executor: Executor { get }
  var releasePool: ReleasePool { get }
}

//#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
//  extension NSObject {
//    func associatedObject<T>(forKey key: String) -> T? {
//      return key.withCString { objc_getAssociatedObject(self, $0) as! T? }
//    }
//
//    func setAssociatedObject<T>(object: T?, forKey key: String) {
//      key.withCString {
//        objc_setAssociatedObject(self, $0, object, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
//      }
//    }
//  }
//#endif
//
//#if os(macOS)
//  import AppKit
//  extension NSResponder : ExecutionContext {
//    public var executor: Executor { return .main }
//  }
//#elseif os(iOS) || os(tvOS) || os(watchOS)
//  import UIKit
//  extension UIResponder : ExecutionContext {
//    public var executor: Executor { return .main }
//  }
//#else
//#endif
