# Integration

This topic describes options of integration.

##### Contents
* [Using Swift Package Manager](#using-swift-package-manager)
* [Using git submodule](#using-git-submodule)
* [Other methods](#other-methods)

## Using [Swift Package Manager](https://github.com/apple/swift-package-manager)
This is the easiest and the most reliable way. Add AsyncNinja dependency to your package.

```swift
import PackageDescription

let package = Package(
    name: "MySuperApp",
    targets: [
    	Target(
    		name: "Core",
    		dependencies: []
    	),
    	Target(
    		name: "MySuperApp",
    		dependencies: ["Core"]
    	),
    ],
	dependencies: [
    	.Package(url: "https://github.com/AsyncNinja/AsyncNinja.git", majorVersion: 0),
    ]
)
``` 

## Using git submodule

```bash
git submodule add https://github.com/AsyncNinja/AsyncNinja.git AsyncNinja
git commit -m "AsyncNinja submodule added"
```

Now you can import files from AsyncNinja/Sources to your project. Having 3rd party framework next to your sources
might sound and looks strange, but it might actually improve performance. Swift can optimize code that uses AsyncNinja
primitives by generics specification [see official documentation](https://github.com/apple/swift/blob/master/docs/OptimizationTips.rst#generics).

## Other methods
Maybe you are wondering if there is support of CocoaPods or Carthage. No there is not. But you can [request it](https://github.com/AsyncNinja/AsyncNinja/issues).