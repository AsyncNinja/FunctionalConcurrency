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

/// Promise that may be manually completed by owner.
final public class Promise<FinalValue> : Future<FinalValue>, MutableFinite {
  public typealias ImmutableFinite = Future<FinalValue>

  private var _container = makeThreadSafeContainer()
  private let releasePool = ReleasePool()
  override public var finalValue: Fallible<FinalValue>? { return (_container.head as? CompletedPromiseState)?.value }

  override public init() { }

  /// **internal use only**
  override public func makeFinalHandler(executor: Executor,
                                        block: @escaping (Fallible<FinalValue>) -> Void) -> FinalHandler? {
    let handler = Handler(executor: executor, block: block, owner: self)
    _container.updateHead {
      switch $0 {
      case let completedState as CompletedPromiseState<FinalValue>:
        handler.handle(completedState.value)
        return $0
      case let incompleteState as SubscribedPromiseState<FinalValue>:
        return SubscribedPromiseState(handler: handler, next: incompleteState)
      case .none:
        return SubscribedPromiseState(handler: handler, next: nil)
      default:
        fatalError()
      }
    }
    return handler
  }

  /// Completes promise with value and returns true.
  /// Returns false if promise was completed before.
  @discardableResult
  final public func tryComplete(with final: Value) -> Bool {
    let completedItem = CompletedPromiseState(value: final)
    let (oldHead, newHead) = _container.updateHead {
      (($0 as! AbstractPromiseState<FinalValue>?)?.isIncomplete ?? true)
        ? completedItem
        : $0
    }
    let didComplete = (completedItem === newHead)
    guard didComplete else { return false }
    
    var nextItem = oldHead
    while let currentItem = nextItem as? SubscribedPromiseState<FinalValue> {
      currentItem.handler?.handle(final)
      nextItem = currentItem.next
    }
    self.releasePool.drain()
    
    return true
  }

  
  public func insertToReleasePool(_ releasable: Releasable) {
    assert((releasable as? AnyObject) !== self) // Xcode 8 mistreats this. This code is valid
    assert((releasable as? Handler)?.owner !== self)
    if !self.isComplete {
      self.releasePool.insert(releasable)
    }
  }
  
  func notifyDrain(_ block: @escaping () -> Void) {
    if self.isComplete {
      block()
    } else {
      self.releasePool.notifyDrain(block)
    }
  }
}

/// **internal use only**
class AbstractPromiseState<T> {
  var isIncomplete: Bool { fatalError() /* abstract */ }
}

/// **internal use only**
final class SubscribedPromiseState<T> : AbstractPromiseState<T> {
  typealias Value = Fallible<T>
  typealias Handler = FutureHandler<T>
  
  weak private(set) var handler: Handler?
  let next: SubscribedPromiseState<T>?
  override var isIncomplete: Bool { return true }
  
  init(handler: Handler, next: SubscribedPromiseState<T>?) {
    self.handler = handler
    self.next = next
  }
}

/// **internal use only**
final class CompletedPromiseState<T> : AbstractPromiseState<T> {
  let value: Fallible<T>
  override var isIncomplete: Bool { return false }
  
  init(value: Fallible<T>) {
    self.value = value
  }
}
