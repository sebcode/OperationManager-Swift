# OperationManager based on NSOperationQueue

This is an example project featuring OperationManager which is a wrapper around [NSOperationQueue](https://developer.apple.com/library/mac/documentation/Cocoa/Reference/NSOperationQueue_class/index.html) written in Swift.

The example use case for this class is a download manager that has to manage and process a queue of download operations, although this could be any kind of operation where some work has to be processed in a queue.

Requirements: The queue processes concurrently a configurable number of download operations. The user should be allowed to

* see a list of all operations (enqueued, active and finished).
* add operations to the queue / remove operations from queue.
* cancel operations.
* retry previously cancelled operations.
* clear finished or cancelled operations from the list.
* reorder operations.

The list of operations are displayed in a NSTableView. There would have been much less code if I would have used Cocoa Bindings, but then I would have lost control over the insert/update/remove animations.

Sebastian Volland - http://github.com/sebcode