//
//  Copyright (c) 2016-2017 Anton Mironov
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

public extension Channel {
  
  /// Adds indexes to update values of the channel
  ///
  /// - Parameters:
  ///   - cancellationToken: `CancellationToken` to use.
  ///     Keep default value of the argument unless you need
  ///     an extended cancellation options of returned channel
  ///   - bufferSize: `DerivedChannelBufferSize` of derived channel.
  ///     Keep default value of the argument unless you need
  ///     an extended buffering options of returned channel
  /// - Returns: channel with tuple (index, update) as update value
  func enumerated(cancellationToken: CancellationToken? = nil,
                  bufferSize: DerivedChannelBufferSize = .default
    ) -> Channel<(Int, Update), Success> {
    
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
      
      var index: OSAtomic_int64_aligned64_t = -1
      return self.map(executor: .immediate,
                      cancellationToken: cancellationToken,
                      bufferSize: bufferSize)
      {
        let localIndex = Int(OSAtomicIncrement64(&index))
        return (localIndex, $0)
      }
      
    #else
      
      var locking = makeLocking()
      var index = 0
      return self.map(executor: .immediate,
                      cancellationToken: cancellationToken,
                      bufferSize: bufferSize)
      {
        locking.lock()
        defer { locking.unlock() }
        let localIndex = index
        index += 1
        return (localIndex, $0)
      }
      
    #endif
  }
  
  /// Makes channel of pairs of update values
  ///
  /// - Parameters:
  ///   - cancellationToken: `CancellationToken` to use.
  ///     Keep default value of the argument unless you need
  ///     an extended cancellation options of returned channel
  ///   - bufferSize: `DerivedChannelBufferSize` of derived channel.
  ///     Keep default value of the argument unless you need
  ///     an extended buffering options of returned channel
  /// - Returns: channel with tuple (update, update) as update value
  func bufferedPairs(cancellationToken: CancellationToken? = nil,
                     bufferSize: DerivedChannelBufferSize = .default
    ) -> Channel<(Update, Update), Success> {
    var locking = makeLocking()
    var previousUpdate: Update? = nil
    
    return self.makeProducer(executor: .immediate,
                             cancellationToken: cancellationToken,
                             bufferSize: bufferSize)
    {
      (value, producer) in
      switch value {
      case let .update(update):
        locking.lock()
        let _previousUpdate = previousUpdate
        previousUpdate = update
        locking.unlock()
        
        if let previousUpdate = _previousUpdate {
          let change = (previousUpdate, update)
          producer.update(change)
        }
      case let .completion(completion):
        producer.complete(with: completion)
      }
    }
  }
  
  /// Makes channel of arrays of update values
  ///
  /// - Parameters:
  ///   - capacity: number of update values of original channel used
  ///     as update value of derived channel
  ///   - cancellationToken: `CancellationToken` to use.
  ///     Keep default value of the argument unless you need
  ///     an extended cancellation options of returned channel
  ///   - bufferSize: `DerivedChannelBufferSize` of derived channel.
  ///     Keep default value of the argument unless you need
  ///     an extended buffering options of returned channel
  /// - Returns: channel with [update] as update value
  func buffered(capacity: Int,
                cancellationToken: CancellationToken? = nil,
                bufferSize: DerivedChannelBufferSize = .default
    ) -> Channel<[Update], Success> {
    var buffer = [Update]()
    buffer.reserveCapacity(capacity)
    var locking = makeLocking()
    
    return self.makeProducer(executor: .immediate,
                             cancellationToken: cancellationToken,
                             bufferSize: bufferSize)
    {
      (value, producer) in
      locking.lock()
      
      switch value {
      case let .update(update):
        buffer.append(update)
        if capacity == buffer.count {
          let localBuffer = buffer
          buffer.removeAll(keepingCapacity: true)
          locking.unlock()
          producer.update(localBuffer)
        } else {
          locking.unlock()
        }
      case let .completion(completion):
        let localBuffer = buffer
        buffer.removeAll(keepingCapacity: false)
        locking.unlock()
        
        if !localBuffer.isEmpty {
          producer.update(localBuffer)
        }
        producer.complete(with: completion)
      }
    }
  }
  
  /// Makes channel that delays each value produced by originial channel
  ///
  /// - Parameters:
  ///   - timeout: in seconds to delay original channel by
  ///   - cancellationToken: `CancellationToken` to use.
  ///     Keep default value of the argument unless you need
  ///     an extended cancellation options of returned channel
  ///   - bufferSize: `DerivedChannelBufferSize` of derived channel.
  ///     Keep default value of the argument unless you need
  ///     an extended buffering options of returned channel
  /// - Returns: delayed channel
  func delayedUpdate(timeout: Double,
                     cancellationToken: CancellationToken? = nil,
                     bufferSize: DerivedChannelBufferSize = .default
    ) -> Channel<Update, Success> {
    return self.makeProducer(executor: .immediate,
                             cancellationToken: cancellationToken,
                             bufferSize: bufferSize)
    {
      (event: Event, producer: BaseProducer<Update, Success>) -> Void in
      Executor.primary.execute(after: timeout) { [weak producer] in
        guard let producer = producer else { return }
        producer.apply(event)
      }
    }
  }
  
  /// Picks latest update value of the channel every interval and sends it
  ///
  /// - Parameters:
  ///   - deadline: to start picking peridic values after
  ///   - interval: interfal for picking latest update values
  ///   - leeway: leeway for timer
  ///   - cancellationToken: `CancellationToken` to use.
  ///     Keep default value of the argument unless you need
  ///     an extended cancellation options of returned channel
  ///   - bufferSize: `DerivedChannelBufferSize` of derived channel.
  ///     Keep default value of the argument unless you need
  /// - Returns: channel
  func debounce(deadline: DispatchTime = DispatchTime.now(),
                interval: Double,
                leeway: DispatchTimeInterval? = nil,
                cancellationToken: CancellationToken? = nil,
                bufferSize: DerivedChannelBufferSize = .default
    ) -> Channel<Update, Success> {
    
    // Test: Channel_TransformTests.testDebounce
    let bufferSize_ = bufferSize.bufferSize(self)
    let producer = Producer<Update, Success>(bufferSize: bufferSize_)
    var locking = makeLocking()
    var latestUpdate: Update? = nil
    var didSendFirstUpdate = false
    
    let timer = DispatchSource.makeTimerSource()
    if let leeway = leeway {
      timer.scheduleRepeating(deadline: DispatchTime.now(), interval: interval, leeway: leeway)
    } else {
      timer.scheduleRepeating(deadline: DispatchTime.now(), interval: interval)
    }
    
    timer.setEventHandler { [weak producer] in
      locking.lock()
      if let update = latestUpdate {
        latestUpdate = nil
        locking.unlock()
        producer?.update(update)
      } else {
        locking.unlock()
      }
    }
    
    timer.resume()
    producer.insertToReleasePool(timer)
    
    let handler = self.makeHandler(executor: .immediate) {
      [weak producer] (event) in
      
      locking.lock()
      defer { locking.unlock() }
      
      switch event {
      case let .completion(completion):
        if let update = latestUpdate {
          producer?.update(update)
          latestUpdate = nil
        }
        producer?.complete(with: completion)
      case let .update(update):
        if didSendFirstUpdate {
          latestUpdate = update
        } else {
          didSendFirstUpdate = true
          producer?.update(update)
        }
      }
    }
    
    self.insertHandlerToReleasePool(handler)
    cancellationToken?.add(cancellable: producer)
    
    return producer
  }
}

// MARK: - Distinct

extension Channel {
  /// Returns channel of distinct update values of original channel.
  /// Requires dedicated equality checking closure
  ///
  /// - Parameters:
  ///   - cancellationToken: `CancellationToken` to use.
  ///     Keep default value of the argument unless you need
  ///     an extended cancellation options of returned channel
  ///   - bufferSize: `DerivedChannelBufferSize` of derived channel.
  ///     Keep default value of the argument unless you need
  ///     an extended buffering options of returned channel
  ///   - isEqual: closure that tells if specified values are equal
  /// - Returns: channel with distinct update values
  func distinct(cancellationToken: CancellationToken? = nil,
                         bufferSize: DerivedChannelBufferSize = .default,
                         isEqual: @escaping (Update, Update) -> Bool
    ) -> Channel<Update, Success> {
    
    var locking = makeLocking()
    var previousUpdate: Update? = nil
    
    return self.makeProducer(executor: .immediate,
                             cancellationToken: cancellationToken,
                             bufferSize: bufferSize)
    {
      (value, producer) in
      switch value {
      case let .update(update):
        locking.lock()
        let _previousUpdate = previousUpdate
        previousUpdate = update
        locking.unlock()
        
        
        if let previousUpdate = _previousUpdate {
          if !isEqual(previousUpdate, update) {
            producer.update(update)
          }
        } else {
          producer.update(update)
        }
      case let .completion(completion):
        producer.complete(with: completion)
      }
    }
  }
}

extension Channel where Update: Equatable {
  
  /// Returns channel of distinct update values of original channel.
  /// Works only for equatable update values
  /// [0, 0, 1, 2, 3, 3, 4, 3] => [0, 1, 2, 3, 4, 3]
  ///
  /// - Parameters:
  ///   - cancellationToken: `CancellationToken` to use.
  ///     Keep default value of the argument unless you need
  ///     an extended cancellation options of returned channel
  ///   - bufferSize: `DerivedChannelBufferSize` of derived channel.
  ///     Keep default value of the argument unless you need
  ///     an extended buffering options of returned channel
  /// - Returns: channel with distinct update values
  public func distinct(cancellationToken: CancellationToken? = nil,
                       bufferSize: DerivedChannelBufferSize = .default
    ) -> Channel<Update, Success> {
    
    // Test: Channel_TransformTests.testDistinctInts
    return distinct(cancellationToken: cancellationToken, bufferSize: bufferSize, isEqual: ==)
  }
}

extension Channel where Update: AsyncNinjaOptionalAdaptor, Update.AsyncNinjaWrapped: Equatable {
  
  /// Returns channel of distinct update values of original channel.
  /// Works only for equatable wrapped in optionals
  /// [nil, 1, nil, nil, 2, 2, 3, nil, 3, 3, 4, 5, 6, 6, 7] => [nil, 1, nil, 2, 3, nil, 3, 4, 5, 6, 7]
  ///
  /// - Parameters:
  ///   - cancellationToken: `CancellationToken` to use.
  ///     Keep default value of the argument unless you need
  ///     an extended cancellation options of returned channel
  ///   - bufferSize: `DerivedChannelBufferSize` of derived channel.
  ///     Keep default value of the argument unless you need
  ///     an extended buffering options of returned channel
  /// - Returns: channel with distinct update values
  public func distinct(cancellationToken: CancellationToken? = nil,
                       bufferSize: DerivedChannelBufferSize = .default
    ) -> Channel<Update, Success> {
    
    // Test: Channel_TransformTests.testDistinctInts
    return distinct(cancellationToken: cancellationToken, bufferSize: bufferSize) {
      $0.asyncNinjaOptionalValue == $1.asyncNinjaOptionalValue
    }
  }
}

extension Channel where Update: Collection, Update.Iterator.Element: Equatable {
  
  /// Returns channel of distinct update values of original channel.
  /// Works only for collections of equatable values
  /// [[1], [1], [1, 2], [1, 2, 3], [1, 2, 3], [1]] => [[1], [1, 2], [1, 2, 3], [1]]
  ///
  /// - Parameters:
  ///   - cancellationToken: `CancellationToken` to use.
  ///     Keep default value of the argument unless you need
  ///     an extended cancellation options of returned channel
  ///   - bufferSize: `DerivedChannelBufferSize` of derived channel.
  ///     Keep default value of the argument unless you need
  ///     an extended buffering options of returned channel
  /// - Returns: channel with distinct update values
  public func distinct(cancellationToken: CancellationToken? = nil,
                       bufferSize: DerivedChannelBufferSize = .default
    ) -> Channel<Update, Success> {
    
    // Test: Channel_TransformTests.testDistinctArray
    return distinct(cancellationToken: cancellationToken, bufferSize: bufferSize) {
      return $0.count == $1.count
        && !zip($0, $1).contains { $0 != $1 }
    }
  }
}

extension Channel where Update: NSObjectProtocol {
  
  /// Returns channel of distinct update values of original channel.
  /// Works only for collections of equatable values
  /// [objectA, objectA, objectB, objectC, objectC, objectA] => [objectA, objectB, objectC, objectA]
  ///
  /// - Parameters:
  ///   - cancellationToken: `CancellationToken` to use.
  ///     Keep default value of the argument unless you need
  ///     an extended cancellation options of returned channel
  ///   - bufferSize: `DerivedChannelBufferSize` of derived channel.
  ///     Keep default value of the argument unless you need
  ///     an extended buffering options of returned channel
  /// - Returns: channel with distinct update values
  public func distinctNSObjects(cancellationToken: CancellationToken? = nil,
                                bufferSize: DerivedChannelBufferSize = .default
    ) -> Channel<Update, Success> {
    
    // Test: Channel_TransformTests.testDistinctNSObjects
    return distinct(cancellationToken: cancellationToken, bufferSize: bufferSize) {
      return $0.isEqual($1)
    }
  }
}

extension Channel where Update: Collection, Update.Iterator.Element: NSObjectProtocol {
  
  /// Returns channel of distinct update values of original channel.
  /// Works only for collections of NSObjects values
  /// [[objectA], [objectA], [objectA, objectB], [objectA, objectB, objectC], [objectA, objectB, objectC], [objectA]] => [[objectA], [objectA, objectB], [objectA, objectB, objectC], [objectA]]
  ///
  /// - Parameters:
  ///   - cancellationToken: `CancellationToken` to use.
  ///     Keep default value of the argument unless you need
  ///     an extended cancellation options of returned channel
  ///   - bufferSize: `DerivedChannelBufferSize` of derived channel.
  ///     Keep default value of the argument unless you need
  ///     an extended buffering options of returned channel
  /// - Returns: channel with distinct update values
  public func distinctCollectionOfNSObjects(cancellationToken: CancellationToken? = nil,
                                            bufferSize: DerivedChannelBufferSize = .default
    ) -> Channel<Update, Success> {
    
    // Test: Channel_TransformTests.testDistinctArrayOfNSObjects
    return distinct(cancellationToken: cancellationToken, bufferSize: bufferSize) {
      return $0.count == $1.count
        && !zip($0, $1).contains { !$0.isEqual($1) }
    }
  }
}