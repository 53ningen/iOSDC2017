import Foundation

public enum Event<T> {
    case next(T)
    case error(Error)
    case completed
}

extension Event {
    public var isStopEvent: Bool {
        switch self {
        case .next: return false
        case .error, .completed: return true
        }
    }
}

public protocol Disposable {
    func dispose()
}

public protocol ObservableType {
    associatedtype E
    func subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == E
}

public protocol ObserverType {
    associatedtype E
    func on(_ event: Event<E>)
}

extension ObserverType {
    public final func onNext(_ element: E) {
        on(.next(element))
    }
    
    public final func onCompleted() {
        on(.completed)
    }
    
    public final func onError(_ error: Swift.Error) {
        on(.error(error))
    }
}

// Swift does not implement abstract methods.
// This method is used as a runtime check to ensure that methods which intended to be abstract
func abstractMethod() -> Never {
    fatalError("abstract method")
}

public class Observable<Element>: ObservableType {
    public typealias E = Element
    
    public func subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == E {
        abstractMethod()
    }
}

class AnonymousObserver<Element>: ObserverType {
    typealias E = Element
    typealias EventHandler = (Event<Element>) -> Void
    private let eventHandler: EventHandler
    private var isStopped: Int32 = 0
    
    public init(_ eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
    }
    
    public func on(_ event: Event<Element>) {
        switch (event) {
        case .next:
            if isStopped == 0 {
                eventHandler(event)
            }
        case .error, .completed:
            if !OSAtomicCompareAndSwap32Barrier(0, 1, &isStopped) {
                return
            }
            eventHandler(event)
        }
    }
}

public protocol SubjectType: ObservableType {
    associatedtype SubjectObserverType : ObserverType
    func asObserver() -> SubjectObserverType
}

protocol UnsubscribeType: class {
    func unsubscribe(key: String)
}

struct SubscriptionDisposable<T>: Disposable {
    weak var ref: UnsubscribeType?
    let key: String
    init(ref: UnsubscribeType, key: String) {
        self.ref = ref
        self.key = key
    }
    public func dispose() {
        ref?.unsubscribe(key: key)
    }
}

struct NopDisposable : Disposable {
    init() {}
    public func dispose() {}
}

public class PublishSubject<Element>:
Observable<Element>, SubjectType, ObserverType, UnsubscribeType {
    public typealias SubjectObserverType = PublishSubject<Element>
    var observers: [String:AnonymousObserver<Element>] = [:]
    
    public override func subscribe<O>
        (_ observer: O) -> Disposable where O : ObserverType, O.E == Element {
        let key = UUID().uuidString
        observers[key] = AnonymousObserver(observer.on)
        return SubscriptionDisposable<Element>(ref: self, key: key)
    }
    
    internal func unsubscribe(key: String) { observers.removeValue(forKey: key) }
    
    public func on(_ event: Event<Element>) { observers.forEach { x in x.value.on(event) } }
    
    public func asObserver() -> PublishSubject<Element> { return self }
}

var isHoge = PublishSubject<Bool>()
var observer = AnonymousObserver<Bool>({ event in
    switch(event) {
    case .next(var value): NSLog(String(value))
    case .error(var error): NSLog(error.localizedDescription)
    case .completed: NSLog("completed")
    }
})

var disopsable = isHoge.subscribe(observer)
isHoge.on(Event.next(true))
isHoge.on(Event.error(NSError(domain: "", code: -1, userInfo: nil )))
isHoge.on(Event.completed)
disopsable.dispose()
