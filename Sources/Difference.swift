import Foundation

fileprivate extension String {
    init<T>(dumping object: T) {
        self.init()
        dump(object, to: &self)
        self = withoutDumpArtifacts
    }

    private var withoutDumpArtifacts: String {
        self.replacingOccurrences(of: "- ", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
}

private func enumLabelFromFirstChild(_ mirror: Mirror) -> String? {
    switch mirror.displayStyle {
    case .enum: return mirror.children.first?.label
    default: return nil
    }
}

fileprivate extension Mirror {
    var displayStyleDescriptor: String {
        switch self.displayStyle {
        case .enum: return "Enum"
        default: return "Child"
        }
    }

    // Used to show "different count" message if mirror has no children,
    // as some displayStyles can have 0 children.
    var canBeEmpty: Bool {
        switch self.displayStyle {
        case .collection,
             .dictionary,
             .set:
            return true
        default:
            return false
        }
    }
}

fileprivate func handleChildless<T>(
    _ expected: T,
    _ received: T,
    _ indentationLevel: Int
) -> String {
    let expectedMirror = Mirror(reflecting: expected)
    let receivedMirror = Mirror(reflecting: received)

    guard !expectedMirror.canBeEmpty else {
        return generateDifferentCountBlock(expected, expectedMirror, received, receivedMirror, indentationLevel)
    }

    let receivedPrintable: String
    let expectedPrintable: String
    if receivedMirror.children.count == 0, expectedMirror.children.count != 0 {
        receivedPrintable = String(dumping: received)
        expectedPrintable = enumLabelFromFirstChild(expectedMirror) ?? String(describing: expected)
    } else if expectedMirror.children.count == 0, receivedMirror.children.count != 0 {
        receivedPrintable = enumLabelFromFirstChild(receivedMirror) ?? String(describing: received)
        expectedPrintable = String(dumping: expected)
    } else {
        receivedPrintable = String(describing: received)
        expectedPrintable = String(describing: expected)
    }
    return "R7" + generateExpectedReceiveBlock(expectedPrintable, receivedPrintable, indentationLevel)
}

private func generateDifferentCountBlock<T>(
    _ expected: T,
    _ expectedMirror: Mirror,
    _ received: T,
    _ receivedMirror: Mirror,
    _ indentationLevel: Int
) -> String {
    let expectedPrintable = "(\(expectedMirror.children.count)) \(expected)"
    let receivedPrintable = "(\(receivedMirror.children.count)) \(received)"
    let header = "R10\(indentation(level: indentationLevel))Different count:\n"
    return header
        + "R1"
        + generateExpectedReceiveBlock(expectedPrintable, receivedPrintable, indentationLevel + 1)
}

/// Compares 2 objects and iterates over their differences
///
/// - Parameters:
///   - lhs: expected object
///   - rhs: received object
///   - closure: iteration closure
fileprivate func diff<T>(_ expected: T, _ received: T, level: Int = 0, closure: (_ description: String) -> Void) {
    let expectedMirror = Mirror(reflecting: expected)
    let receivedMirror = Mirror(reflecting: received)

    guard expectedMirror.children.count != 0, receivedMirror.children.count != 0 else {
        if String(dumping: received) != String(dumping: expected) {
            closure(handleChildless(expected, received, level))
        }
        return
    }

    let hasDiffNumOfChildren = expectedMirror.children.count != receivedMirror.children.count
    switch (expectedMirror.displayStyle, receivedMirror.displayStyle) {
    case (.collection?, .collection?) where hasDiffNumOfChildren,
         (.dictionary?, .dictionary?) where hasDiffNumOfChildren,
         (.set?, .set?) where hasDiffNumOfChildren:
        let toPrint = generateDifferentCountBlock(expected, expectedMirror, received, receivedMirror, level)
        closure(toPrint)
        return
    case (.dictionary?, .dictionary?):
        if let expectedDict = expected as? Dictionary<AnyHashable, Any>,
            let receivedDict = received as? Dictionary<AnyHashable, Any> {
            expectedDict.keys.forEach { key in
                var results = [String]()
                diff(expectedDict[key], receivedDict[key], level: level + 1) { diff in
                    results.append(diff)
                }
                if !results.isEmpty {
                    let header = "R2\(indentation(level: level))Child key \(key.description):\n"
                    closure(header + results.joined())
                }
            }
            return
        }

    case (.set?, .set?):
        if let expectedSet = expected as? Set<AnyHashable>,
            let receivedSet = received as? Set<AnyHashable> {
            let uniqueExpected = expectedSet.subtracting(receivedSet)

            var results = [String]()
            uniqueExpected.forEach { unique in
                results.append("R3 SetElement missing: \(unique.description)\n")
            }

            if !uniqueExpected.isEmpty {
                closure(results.joined(separator: "\(indentation(level: max(level + 1, 1)))"))
            }
            return
        }
    case (.enum?, .enum) where hasDiffNumOfChildren:
        closure("""
            R4 Different count:
            \(indentation(level: level))Received: \(received) (\(receivedMirror.children.count))
            \(indentation(level: level))Expected: \(expected) (\(expectedMirror.children.count))\n
            """)
        return
    case (.enum?, .enum?) where expectedMirror.children.first?.label != receivedMirror.children.first?.label:
        let expectedPrintable = expectedMirror.children.first?.label ?? "UNKNOWN"
        let receivedPrintable = receivedMirror.children.first?.label ?? "UNKNOWN"

        closure("R5" + generateExpectedReceiveBlock(expectedPrintable, receivedPrintable, level))
        return
//        closure("\(indentation(level: level))R5 Received: \(received) Expected: \(expected)\n")

//    case (.optional?, .optional?) where hasDiffNumOfChildren:

    default:
        break
    }

    let zipped = zip(expectedMirror.children, receivedMirror.children)
    zipped.forEach { (lhs, rhs) in
        let leftDump = String(dumping: lhs.value)
        if leftDump != String(dumping: rhs.value) {
            if let notPrimitive = Mirror(reflecting: lhs.value).displayStyle/*, notPrimitive != .tuple*/ {
                var results = [String]()
                diff(lhs.value, rhs.value, level: level + 1) { diff in
                    results.append(diff)
                }
                if !results.isEmpty {
                    closure("R8\(indentation(level: level))\(expectedMirror.displayStyleDescriptor) \(lhs.label ?? ""):\n" + results.joined())
                }
            } else { // todo maybe remove
                let childName = "R9\(indentation(level: level))\(expectedMirror.displayStyleDescriptor) \(lhs.label ?? ""):\n"
                closure(childName + "R6" + generateExpectedReceiveBlock(String(describing: lhs.value), String(describing: rhs.value), level + 1))
//                closure("\(lhs.label ?? "") received: \(rhs.value) expected: \(lhs.value)\n")
            }
        }
    }
}

private func generateExpectedReceiveBlock(
    _ expected: String,
    _ received: String,
    _ indentationLevel: Int
) -> String {
    let indentationSpacing = indentation(level: indentationLevel)
    return """
    \(indentationSpacing)Received: \(received)
    \(indentationSpacing)Expected: \(expected)

    """
    //"\(indentationSpacing)Received: \(received)\n\(indentationSpacing)Expected: \(expected)\n"
}

private func indentation(level: Int) -> String {
    return (0..<level).reduce("") { acc, _ in acc + "|\t" }
}

/// Builds list of differences between 2 objects
///
/// - Parameters:
///   - expected: Expected value
///   - received: Received value
/// - Returns: List of differences
public func diff<T>(_ expected: T, _ received: T) -> [String] {
    var all = [String]()
    diff(expected, received) { all.append($0) }
    return all
}

/// Prints list of differences between 2 objects
///
/// - Parameters:
///   - expected: Expected value
///   - received: Received value
public func dumpDiff<T: Equatable>(_ expected: T, _ received: T) {
    // skip equal
    guard expected != received else {
        return
    }

    diff(expected, received).forEach { print($0) }
}

/// Prints list of differences between 2 objects
///
/// - Parameters:
///   - expected: Expected value
///   - received: Received value
public func dumpDiff<T>(_ expected: T, _ received: T) {
    diff(expected, received).forEach { print($0) }
}

// TO CHECK:
//DONE Enum with different contents
// Enum with different label
// Enum with nil, rather than a value
