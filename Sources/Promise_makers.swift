//
//  Promise_makers.swift
//  AsyncNinja
//
//  Created by Sergiy Vynnychenko on 3/25/19.
//

import Foundation

// MARK: -
/// Convenience constructor of Promise
/// Gives an access to an underlying Promise to a provided block
public func promise<T>(
  executor: Executor = .immediate,
  after timeout: Double = 0,
  cancellationToken: CancellationToken? = nil,
  _ block: @escaping (_ promise: Promise<T>) throws -> Void) -> Promise<T> {
  let promise = Promise<T>()
  
  cancellationToken?.add(cancellable: promise)
  
  executor.execute(after: timeout) { [weak promise] (originalExecutor) in
    if cancellationToken?.isCancelled ?? false {
      promise?.cancel(from: originalExecutor)
    } else if let promise = promise {
      do    { try block(promise) }
      catch { promise.fail(error) }
    }
  }
  
  return promise
}

// MARK: -
/// Convenience constructor of Promise
/// Gives an access to an underlying Promise to a provided block
public func promise<C: ExecutionContext, T>(
  context: C,
  executor: Executor? = nil,
  after timeout: Double = 0,
  cancellationToken: CancellationToken? = nil,
  _ block: @escaping (_ context: C, _ promise: Promise<T>) throws -> Void) -> Promise<T> {
  
  return promise(executor: executor ?? context.executor,
                 after: timeout,
                 cancellationToken: cancellationToken) { promise in
                  
                  context.addDependent(cancellable: promise)
                  try block(context, promise)
  }
}
