# `Future`
This document describes concept and use of `Future`.

##### Contents
* [Concept](#concept)
    * [Example: Solution based on callbacks](#solution-based-on-callbacks)
    * [Example: Solution based on futures](#solution-based-on-futures)
*  [Reference](#reference)
    *  [Creating `Future`](#creating-future)
    *  [Transforming `Future`](#transforming-future)
    *  [Combining `Future`s](#combining-futures)
    *  [Changing Mutable State with Future](#changing-mutable-state-with-future)

##Concept
[As Wikipedia says](https://en.wikipedia.org/wiki/Futures_and_promises) `Future` is an object that acts as a proxy for a result that is initially unknown, usually because the computation of its value is yet incomplete. 

Straightforward solution will be using callback closure.

```swift
func perform(request: Request, callback: @escaping (Response) -> Void)
```

But this solution has multiple disadvantages:

* so called ["callback hell"](http://callbackhell.com) or ["pyramid of doom"](https://en.wikipedia.org/wiki/Pyramid_of_doom_(programming))
* combining multiple asynchronous operations is a complete disaster
*  it is hard to think of response as a result of operation because it placed inside function arguments
* be very attentive to memory management within callback closure

Function declaration that incorporates `Future` will look like this:

```swift
func perform(request: Request) -> Future<Response>
```

Solutions based on `Future`

* are shorter
* you are getting something as returned value
* are designed to be highly combinable
* AsyncNinja's [memory management](https://github.com/AsyncNinja/AsyncNinja/blob/master/Documentation/MemoryManagement.md) helps to avoid majority of memory issues

#### Example

##### Solution based on callbacks
```swift
protocol MaterialsProvider {
  func provideRubber(_ callback: (Rubber) -> Void)
  func provideMetal(_ callback: (Metal) -> Void)
}

protocol CarFactory {
  var materialsProvider: MaterialsProvider { get }
  func makeWheel(_ callback: @escaping (Car.Wheel) -> Void)
  func makeBody(_ callback: @escaping (Car.Body) -> Void)
  func makeCar(_ callback: @escaping (Car) -> Void)
}

extension CarFactory {
  func makeWheel(_ callback: @escaping (Car.Wheel) -> Void) {
	self.materialsProvider.provideRubber { rubber in
	  // use rubber to make wheel
	  callback(wheel)
	}
  }

  func makeBody(_ callback: @escaping (Car.Body) -> Void) {
	self.materialsProvider.provideMetal { metal in
	  // use metal to make body
	  callback(body)
	}
  }

  func makeCar(_ callback: @escaping (Car) -> Void) {
	let group = DispatchGroup()

	var body: Car.Body? = nil
	group.enter()
	makeBody {
	  body = $0
	  group.leave()
	}

	let sema = DispatchSemaphore(value: 1)
	let numberOfWheels = 4
	var wheels = Array<Car.Wheel?>(repeating: nil, count: numberOfWheels)
	for index in 0..<numberOfWheels {
	  group.enter()
	  makeWheel {
		sema.wait()
		wheels[index] = $0
		sema.signal()
		group.leave()
	  }
	}

	DispatchQueue.global(qos: .utility).async(group: group) {
	  // use body and wheels to make car
	  callback(car)
	}
  }
}
```
##### Solution based on futures
```swift
protocol MaterialsProvider {
  func provideRubber() -> Future<Rubber>
  func provideMetal() -> Future<Metal>
}

protocol CarFactory {
  var materialsProvider: MaterialsProvider { get }
  func makeWheel() -> Future<Car.Wheel>
  func makeBody() -> Future<Car.Body>
  func makeCar() -> Future<Car>
}

extension CarFactory {
  func makeWheel() -> Future<Car.Wheel> {
	return self.materialsProvider
	  .provideRubber()
	  .map { rubber -> Car.Wheel in
		// use rubber to make wheel
		return wheel
	}
  }

  func makeBody() -> Future<Car.Body> {
	return self.materialsProvider
	  .provideMetal()
	  .map { metal -> Car.Body in
		// use metal to make body
		return body
	}
  }

  func makeCar() -> Future<Car> {
	let futureBody = self.makeBody()
	let futureWheels = (0..<4).map { _ in self.makeWheel() }
	return zip(futureBody, futureWheels)
	  .map { (body, wheels) in
		// use body and wheels to make car
		return car
	}
  }
}
```

## Reference
### Creating `Future`

#### `Future` as a result of asynchronous operation
In most cases, initial future is a result of the asynchronous operation.

###### Simple
```swift
/* regular */
func future<T>(executor: Executor, block: @escaping () throws -> T) -> Future<T>

/* contextual */
func future<T, U : ExecutionContext>(context: U, executor: Executor? = nil, block: @escaping (U) throws -> T) -> Future<T>
```

###### Delayed

```swift
/* regular */
func future<T>(executor: Executor, after timeout: Double, block: @escaping () throws -> T) -> Future<T>

/* contextual */
func future<T, U : ExecutionContext>(context: U, executor: Executor?, after timeout: Double, block: @escaping (U) throws -> T) -> Future<T>
```

#### `Future` with predefined value
In some cases, it is convenient to make future with a predefined value.

```swift
func future<T>(value: Fallible<T>) -> Future<T>
func future<T>(success: T) -> Future<T>`
func future<T>(failure: Swift.Error) -> Future<T>
```

#### `Promise`
`Promise` is a specific subclass of `Future` that can be instantiated with public initializer and can be manually completed with `func complete(with final: Value) -> Bool` and `func complete(with future: Future<Value>)`. `Promise` is useful when you have to manage completion manually. Bridging from API based on callbacks is a very common case of using `Promise`:

```swift
func perform(request: Request) -> Future<Response> {
	let promise = Promise<Response>
	_oldAPI.perform(request: request) { [weak promise] in
		promise?.succeed(with: $0)
	}
	return promise
}
```

There is a specific kind of promise called `Promise` is promise with `Fallible` value type. It can be canceled manually.

### Transforming `Future`
Transform value when in becomes available into another value.

```swift
extension Future {
  /* regular */
  func mapCompletion<T>(executor: Executor = .primary, transform: @escaping (Fallible<Success>) throws -> T) -> Future<T>
  func map<T>(executor: Executor = .primary, transform: @escaping (Success) throws -> T) -> Future<T>
  func recover(executor: Executor = .primary, transform: @escaping (Swift.Error) throws -> Success) -> Future<Success> 

  /* contextual */
  func mapCompletion<T, U: ExecutionContext>(context: U, executor: Executor? = nil,
  		                                     transform: @escaping (U, Fallible<Success>) throws -> T) -> Future<T>
  func map<T, U: ExecutionContext>(context: U, executor: Executor? = nil,
  								   transform: @escaping (U, Success) throws -> T) -> Future<T>
  func recover<U: ExecutionContext>(context: U, executor: Executor? = nil,
                                    transform: @escaping (U, Swift.Error) throws -> Success) -> Future<Success>
                                    
  /* delayed */
  delayed(timeout: Double) -> Future<Success>
}
```

### Combining `Future`s
Sometimes there is a possibility to perform multiple independent operations and use combined results. AsyncNinja provides multiple ways to do this.

```swift
/* zipping few `Future`s with different value types */
func zip<A, B>(_ futureA: Future<A>, _ futureB: Future<B>) -> Future<(A, B)>
func zip<A, B, C>(_ futureA: Future<A>, _ futureB: Future<B>, _ futureC: Future<C>) -> Future<(A, B, C)>

/* combining collection of `Future`s into single one */
func Collection<Future<Success>>.joined() -> Future<[Value]>

/* reducing over collection of `Future`s into single `Future` of accumulated result */
func Collection<Future<Value>>.reduce<Result>(executor: Executor, initialResult: Result, nextPartialResult: @escaping (Result, Success) throws -> Result) -> Future<Result>

/* asynchrounously processing each element of collection and combining then unto a single `Future` */
func Collection<Element>.asyncMap<T>(executor: Executor, ..., transform: (Element) -> T) -> Future<[T]>
```

### Changing Mutable State with `Future`
After creation, transformations and combination of futures comes time to store results somewhere. In oppose to previous operations this operation is 100% impure.

#####These are contextual variants. They are preferred because of [memory management](https://github.com/AsyncNinja/AsyncNinja/blob/master/Documentation/MemoryManagement.md) considerations.
```swift
extension Future {
  func onComplete<U: ExecutionContext>(context: U, executor: Executor? = nil, block: @escaping (U, Fallible<Success>) -> Void)
  func onSuccess<U: ExecutionContext>(context: U, executor: Executor? = nil, block: @escaping (U, Success) -> Void)
  func onFailure<U: ExecutionContext>(context: U, executor: Executor? = nil, block: @escaping (U, Swift.Error) -> Void)
}

/* example of usage */
extension MyViewController {
  func present(personWithID identifier: String) {
	self.myService.person(identifier: identifier)
	  .onComplete(context: self) { (self, personOrError) in

		switch personOrError {
		case .success(let person):
		  self.present(person: person)
		case .failure(let error):
		  self.present(error: error)
		}
	
	}
  }
}
```

#####These are non-contextual variants. Please try to avoid using them as much as you can.
```swift
extension Future {
  func onComplete(executor: Executor = .primary, block: @escaping (Fallible<Success>) -> Void)
  func onSuccess(executor: Executor = .primary, block: @escaping (Success) -> Void)
  func onFailure(executor: Executor = .primary, block: @escaping (Swift.Error) -> Void)
}

/* example of usage */
extension MyViewController {
  @objc func legacy_fetch(personWithID identifier: String, callback: @escaping (Fallible<Person?>) -> Void) {
  	// provided callback must be called no matter what
	self.myService.person(identifier: identifier)
	  .onComplete(block: callback)
  }
}
```