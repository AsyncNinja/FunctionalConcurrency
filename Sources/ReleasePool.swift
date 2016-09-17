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

public typealias Releasable = Any

final public class ReleasePool : ThreadSafeContainer {
  typealias ThreadSafeItem = ReleasePoolItem

  var head: ThreadSafeItem? = nil

  public init() { }

  #if os(Linux)
  let sema = DispatchSemaphore(value: 1)
  public func synchronized<T>(_ block: () -> T) -> T {
  self.sema.wait()
  defer { self.sema.signal() }
  return block()
  }
  #endif

  public func insert(_ releasable: Releasable) {
    self.updateHead { .replace(ReleasableReleasePoolItem(object: releasable, next: $0)) }
  }

  public func notifyDrain(_ block: @escaping () -> Void) {
    self.updateHead { .replace(NotifyReleasePoolItem(notifyBlock: block, next: $0)) }
  }

  public func drain() {
    self.updateHead { _ in .remove }
  }
}

class ReleasePoolItem {
  let next: ReleasePoolItem?

  init(next: ReleasePoolItem?) {
    self.next = next
  }
}

final class NotifyReleasePoolItem : ReleasePoolItem {
  let notifyBlock: () -> Void

  init (notifyBlock: @escaping () -> Void, next: ReleasePoolItem?) {
    self.notifyBlock = notifyBlock
    super.init(next: next)
  }

  deinit {
    self.notifyBlock()
  }
}

final class ReleasableReleasePoolItem : ReleasePoolItem {
  let object: Releasable

  init(object: Releasable, next: ReleasePoolItem?) {
    self.object = object
    super.init(next: next)
  }
}