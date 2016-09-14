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

/// Future is a proxy of value that will be available at some point in the future.
public class Future<T> : Finite {
  public typealias FinalValue = T
  public typealias Value = FinalValue
  public typealias Handler = FutureHandler<Value>
  public typealias FinalHandler = Handler

  /// Base future is **abstract**.
  ///
  /// Use `Promise` or `future(executor:block)` or `future(context:executor:block)` to make future.
  init() { }

  /// **Internal use only**.
  public func makeFinalHandler(executor: Executor, block: @escaping (FinalValue) -> Void) -> FinalHandler? {
    /* abstract */
    fatalError()
  }
}

public extension Future {
  final func map<T>(executor: Executor = .primary, transform: @escaping (FinalValue) -> T) -> Future<T> {
    return self.mapFinal(executor: executor, transform: transform)
  }

  final func map<T>(executor: Executor = .primary, transform: @escaping (FinalValue) throws -> T) -> FallibleFuture<T> {
    return self.mapFinal(executor: executor, transform: transform)
  }

  final func map<U: ExecutionContext, V>(context: U, executor: Executor? = nil, transform: @escaping (U, FinalValue) throws -> V) -> FallibleFuture<V> {
    return self.mapFinal(context: context, executor: executor, transform: transform)
  }
}

public extension Finite where FinalValue : _Fallible {
  func map<T>(executor: Executor = .primary, transform: @escaping (FinalValue) throws -> T) -> FallibleFuture<T> {
    return self.mapFinal(executor: executor, transform:transform)
  }
}

/// Asynchrounously executes block on executor and wraps returned value into future
public func future<T>(executor: Executor, block: @escaping () -> T) -> Future<T> {
  let promise = Promise<T>()
  executor.execute { [weak promise] in promise?.complete(with: block()) }
  return promise
}

/// Asynchrounously executes block on executor and wraps returned value into future
public func future<T>(executor: Executor, block: @escaping () throws -> T) -> FallibleFuture<T> {
  return future(executor: executor) { fallible(block: block) }
}

/// Asynchrounously executes block after timeout on executor and wraps returned value into future
public func future<T>(executor: Executor = .primary, after timeout: Double, block: @escaping () -> T) -> Future<T> {
  let promise = Promise<T>()
  executor.execute(after: timeout) { [weak promise] in
    guard let promise = promise else { return }
    promise.complete(with: block())
  }
  return promise
}

/// Asynchrounously executes block after timeout on executor and wraps returned value into future
public func future<T>(after timeout: Double, block: @escaping () throws -> T) -> FallibleFuture<T> {
  return future(after: timeout) { fallible(block: block) }
}

public func future<T, U : ExecutionContext>(context: U, executor: Executor? = nil, block: @escaping (U) throws -> T) -> FallibleFuture<T> {
  return future(executor: executor ?? context.executor) { [weak context] () -> T in
    guard let context = context
      else { throw ConcurrencyError.contextDeallocated }

    return try block(context)
  }
}

/// **Internal use only**
///
/// Each subscription to a future value will be expressed in such handler.
/// Future will accumulate handlers until completion or deallocacion.
final public class FutureHandler<T> {
  let executor: Executor
  let block: (T) -> Void
  let owner: Future<T>

  init(executor: Executor, block: @escaping (T) -> Void, owner: Future<T>) {
    self.executor = executor
    self.block = block
    self.owner = owner
  }

  func handle(_ value: T) {
    self.executor.execute { self.block(value) }
  }
}
