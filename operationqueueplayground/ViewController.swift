//
//  ViewController.swift
//  operationqueueplayground
//
//  Created by Sebastian Volland on 30/07/15.
//  Copyright © 2015 Sebastian Volland. All rights reserved.
//

import Cocoa

class ExampleOperation: Operation {

    override func start() {
        hasStarted = true

        if cancelled {
            operationState = .Finished
            return
        }

        operationState = .Executing

        while process() { }

        operationState = .Finished
    }

    func process() -> Bool {
        if cancelled {
            return false
        }

        if paused {
            sleep(1)
            return true
        }

        usleep(1000000 / (arc4random_uniform(50) + 1))
        ++progress

        return progress < 100
    }

    override func copyForRetry() -> Operation? {
        guard didCopy == false else {
            return nil
        }

        guard canRetry else {
            return nil
        }

        let op = ExampleOperation()
        op.name = self.name
        op.progress = self.progress
        op.paused = self.paused
        didCopy = true
        return op
    }

}

class OperationCell: NSTableCellView {

    @IBOutlet var cancelButton: NSButton?
    @IBOutlet var clearButton: NSButton?

}

let OperationIndexPathPastBoardType = "OperationIndexPathPastBoardType"

class ViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    @IBOutlet var tableView: NSTableView?

    @IBOutlet var addOperationButton: NSButton?
    @IBOutlet var pauseButton: NSButton?
    @IBOutlet var cancelButton: NSButton?
    @IBOutlet var clearButton: NSButton?
    @IBOutlet var sliderControl: NSSlider?

    @IBOutlet var statusLabel: NSTextField?

    var operationManager = OperationManager()

    override func viewDidLoad() {
        super.viewDidLoad()

        operationManager.didInsertOperation = { (index, operation) in
            self.tableView?.insertRowsAtIndexes(NSIndexSet(index: index), withAnimation: NSTableViewAnimationOptions.EffectFade)
        }

        operationManager.didRemoveOperation = { (index, operation) in
            self.tableView?.removeRowsAtIndexes(NSIndexSet(index: index), withAnimation: NSTableViewAnimationOptions.EffectFade)
        }

        operationManager.didUpdateOperation = { (index, operation) in
            self.tableView?.reloadDataForRowIndexes(NSIndexSet(index: index), columnIndexes: NSIndexSet(index: 0))
        }

        updateStatus()

        NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: "updateStatus", userInfo: nil, repeats: true)

        tableView?.registerForDraggedTypes([OperationIndexPathPastBoardType])
    }

    // MARK: Status timer

    func updateStatus() {
        statusLabel?.stringValue = "Total operations: \(operationManager.operations.count) "
            + "- Zombies: \(operationManager.zombieCount) "
            + "- In queue: \(operationManager.operationQueue.operations.count)"
            + "- maxConcurrentOperationCount: \(operationManager.operationQueue.maxConcurrentOperationCount)"
    }

    // MARK: Actions

    @IBAction func pressAddOperation(sender: AnyObject?) {
        struct Static {
            static var counter = 0
        }

        let op = ExampleOperation()
        op.name = "Operation \(++Static.counter)"

        operationManager.add(op)
    }

    @IBAction func pressPause(sender: AnyObject?) {
        if operationManager.paused == false {
            operationManager.pauseAll()
        } else {
            operationManager.resumeAll()
        }

        pauseButton?.title = operationManager.paused ? "Resume" : "Pause"
    }

    @IBAction func pressCancel(sender: AnyObject?) {
        operationManager.cancelAll()
    }

    @IBAction func pressClear(sender: AnyObject?) {
        operationManager.clearAll()
    }

    @IBAction func cellPressCancel(sender: AnyObject) {
        if let button = sender as? NSButton,
            let row = tableView?.rowForView(button) where row >= 0 {
                let operation = operationManager.operations[row]

                if operation.canCancel {
                    operation.cancel()
                } else if operation.canRetry {
                    operationManager.retry(operation)
                }
        }
    }

    @IBAction func cellPressClear(sender: AnyObject) {
        if let button = sender as? NSButton,
            let row = tableView?.rowForView(button) {
                let operation = operationManager.operations[row]
                operationManager.clear(operation)
        }
    }

    // MARK: Slider

    @IBAction func sliderValueChanged(sender: AnyObject) {
        operationManager.operationQueue.maxConcurrentOperationCount = sliderControl!.integerValue
        updateStatus()
    }

    // MARK: Table

    func tableView(tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
        guard let data = info.draggingPasteboard().dataForType(OperationIndexPathPastBoardType) else {
            return false
        }

        guard let indexPaths = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? NSIndexSet where indexPaths.count == 1 else {
            return false
        }

        guard info.draggingSource() as? NSTableView == tableView else {
            return false
        }

        let srcIndex = indexPaths.firstIndex
        let destIndex = row - (row > srcIndex ? 1 : 0)

        let operation = operationManager[srcIndex]
        tableView.moveRowAtIndex(srcIndex, toIndex: destIndex)
        operationManager.operations.removeAtIndex(srcIndex)
        operationManager.operations.insert(operation, atIndex: destIndex)
        operationManager.requeue()

        return true
    }

    func tableView(tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
        return dropOperation == .Above ? .Move : .None
    }

    func tableView(tableView: NSTableView, writeRowsWithIndexes rowIndexes: NSIndexSet, toPasteboard pboard: NSPasteboard) -> Bool {
        guard rowIndexes.count == 1 else {
            return false
        }

        pboard.declareTypes([OperationIndexPathPastBoardType], owner: self)
        let data = NSKeyedArchiver.archivedDataWithRootObject(rowIndexes)
        pboard.setData(data, forType: OperationIndexPathPastBoardType)
        return true
    }

    func tableView(tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 40
    }

    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        return operationManager.count
    }

    func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableColumn == nil {
            return nil
        }

        let operation = operationManager[row]

        switch tableColumn!.identifier {
        case "OperationColumn":
            if let cellView = tableView.makeViewWithIdentifier("OperationCell", owner: nil) as? OperationCell {
                cellView.textField?.stringValue = "\(operation.description)"

                cellView.clearButton?.enabled = operation.canClear

                cellView.cancelButton?.enabled = operation.canRetry || operation.canCancel
                if operation.canRetry {
                    cellView.cancelButton?.title = "Retry"
                } else {
                    cellView.cancelButton?.title = "Cancel"
                }

                return cellView
            }
            return nil
        default:
            return nil
        }
    }

}
