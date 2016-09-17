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

final public class FiniteProducer<T, U> : FiniteChannel<T, U>, ThreadSafeContainer {
  typealias ThreadSafeItem = FiniteProducerState<PeriodicalValue, FinalValue>
  typealias RegularState = RegularFiniteProducerState<PeriodicalValue, FinalValue>
  typealias FinalState = FinalFiniteProducerState<PeriodicalValue, FinalValue>
  var head: ThreadSafeItem?

  override public init() { }

  #if os(Linux)
  let sema = DispatchSemaphore(value: 1)
  public func synchronized<T>(_ block: () -> T) -> T {
  self.sema.wait()
  defer { self.sema.signal() }
  return block()
  }
  #endif

  /// **internal use only**
  override public func makeHandler(executor: Executor,
                                   block: @escaping (Value) -> Void) -> Handler? {
    let handler = Handler(executor: executor, block: block)
    self.updateHead {
      switch $0 {
      case .none:
        return .replace(RegularState(handler: handler, next: nil))
      case let regularState as RegularState:
        return .replace(RegularState(handler: handler, next: regularState))
      case let finalState as FinalState:
        handler.handle(.final(finalState.final))
        return .keep
      default:
        fatalError()
      }
    }

    return handler
  }

  private func notify(_ value: Value, head: ThreadSafeItem?) -> Bool {
    guard let regularState = head as? RegularState else { return false }
    var nextItem: RegularState? = regularState
    
    while let currentItem = nextItem {
      currentItem.handler?.handle(value)
      nextItem = currentItem.next
    }
    return true
  }
  
  public func send(periodical: PeriodicalValue) -> Bool {
    return self.notify(.periodical(periodical), head: self.head)
  }
  
  public func send(final: FinalValue) -> Bool {
    let (oldHead, newHead) = self.updateHead {
      switch $0 {
      case .none:
        return .replace(FinalState(final: final))
      case is RegularState:
        return .replace(FinalState(final: final))
      case is FinalState:
        return .keep
      default:
        fatalError()
      }
    }
    
    guard nil != newHead else { return false }
    
    return self.notify(.final(final), head: oldHead)
  }
}

class FiniteProducerState<T, U> {
  typealias Value = FiniteChannelValue<T, U>
  typealias Handler = FiniteChannelHandler<T, U>
  
  init() { }
}

final class RegularFiniteProducerState<T, U> : FiniteProducerState<T, U> {
  weak var handler: Handler?
  let next: RegularFiniteProducerState<T, U>?
  
  init(handler: Handler, next: RegularFiniteProducerState<T, U>?) {
    self.handler = handler
    self.next = next
  }
}

final class FinalFiniteProducerState<T, U> : FiniteProducerState<T, U> {
  let final: U
  
  init(final: U) {
    self.final = final
  }
}