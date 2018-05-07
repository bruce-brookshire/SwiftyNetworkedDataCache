///Allows the DataCache to find and cache the data at the url specified
public protocol CachedDataOwner: Hashable {
    ///url path to download data from
    var urlPath: String {get}
    
    ///Datatype for the the cache
    associatedtype ProcessedData
    
    ///Used to process the data received from a network request
    static func processData(data: Data) -> ProcessedData?
}

///The result type of the data fetch operation
enum CacheFetchResult {
    case CACHED, FETCHED, BADREQUEST, DATAPROCESSINGISSUE
}

///Used to limit the size of the data cache
///while minimizing the number of network requests
open class DataCache<T:CachedDataOwner> {
    
    typealias ProcessedData = T.ProcessedData
    private var dataCache: CappedCache<T>
    fileprivate var parentWrapperDict: [T: DataWrapper<T>] = [:]
    
    public var maxSize: Int {
        set { dataCache.updateMaxSize(maxSize: maxSize) }
        get { return dataCache.maxSize }
    }
    
    init(maxSize: Int) {
        self.dataCache = CappedCache<T>(maxSize: maxSize)
    }
    
    ///Returns the profile photo if available.
    /// - parameter parent: parent object to fetch data for
    /// - parameter completion: NOT GUARANTEED TO RUN ON MAIN THREAD
    func fetchData(forParent parent: T, _ completion: @escaping (ProcessedData?, CacheFetchResult) -> Void) {
        let wrapper: DataWrapper<T>
        
        if let dataWrapper = parentWrapperDict[parent] {
            wrapper = dataWrapper
        } else {
            let dataWrapper = DataWrapper<T>(parent, self)
            parentWrapperDict[parent] = dataWrapper
            wrapper = dataWrapper
        }
        
        wrapper.fetchingCondition.lock()
        
        if let object = dataCache.get(wrapper) {
            wrapper.fetchingCondition.unlock()
            completion(object, .CACHED)
        }
        else if wrapper.isFetching {
            wrapper.fetchingCondition.unlock()
            Thread {
                wrapper.fetchingCondition.lock()
                
                while wrapper.isFetching { wrapper.fetchingCondition.wait() }
                
                wrapper.fetchingCondition.unlock()
                completion(self.dataCache.get(wrapper), .CACHED)
                }.start()
        }
        else {
            wrapper.isFetching = true
            let path = wrapper.dataParent.urlPath
            wrapper.fetchingCondition.unlock()
            
            URLSession.shared.dataTask(with: URL(string: path)!) { (data, response, error) in
                wrapper.fetchingCondition.lock()
                
                var completionObject: ProcessedData?
                var result: CacheFetchResult = .BADREQUEST
                
                defer {
                    wrapper.fetchingCondition.broadcast()
                    wrapper.fetchingCondition.unlock()
                    if completionObject == nil {
                        self.dataCache.invalidate(wrapper)
                    }
                    completion(completionObject, result)
                }
                
                //test for successful network request
                if let data = data,
                    error == nil,
                    [200,204].contains((response as? HTTPURLResponse)?.statusCode)
                {
                    completionObject = T.processData(data: data)
                    if completionObject != nil {
                        result = .FETCHED
                        self.dataCache.set(wrapper, completionObject!)
                    }
                    else {
                        result = .DATAPROCESSINGISSUE
                    }
                    wrapper.isFetching = false
                }
                }.resume()
        }
    }
    
    
    ///Removes the value from the cache for the parent
    /// - returns: the value stored, or nil if none found
    func removeValue(forParent parent: T) -> ProcessedData? {
        if let wrapper = parentWrapperDict[parent] {
            return dataCache.invalidate(wrapper)
        } else {
            return nil
        }
    }
}

///Caps cached items at a certain value. Inserting an element in a full cache
///will trim one element from the cache in FIFO order
fileprivate class CappedCache <T: CachedDataOwner> {
    
    typealias Wrapper = DataWrapper<T>
    typealias ProcessedData = T.ProcessedData
    
    private var cache: [Wrapper : ProcessedData] = [:]
    private var queue = Queue<Wrapper>()
    fileprivate var maxSize: Int
    
    init(maxSize: Int = 25) {
        self.maxSize = maxSize
    }
    
    ///Sets the element for the value and trims the cache if necessary
    func set(_ key: Wrapper,_ value: ProcessedData) {
        if queue.count() == maxSize {
            let expiredKey = queue.getFront()!
            expiredKey.invalidate()
            cache.removeValue(forKey: expiredKey)
        }
        queue.enqueue(key)
        cache[key] = value
    }
    
    ///Gets the element for the value in the cache if
    ///the element exists
    func get(_ key: Wrapper) -> ProcessedData? {
        return cache[key]
    }
    
    ///Updates the max size and trims the cache if necessary
    func updateMaxSize(maxSize: Int) {
        self.maxSize = maxSize
        while queue.count() > maxSize {
            let expiredKey = queue.getFront()!
            expiredKey.invalidate()
            cache.removeValue(forKey: expiredKey)
        }
    }
    
    func invalidate(_ key: Wrapper) -> ProcessedData? {
        queue.remove(element: key)
        key.invalidate()
        return cache.removeValue(forKey: key)
    }
}

fileprivate class DataWrapper<T: CachedDataOwner>: Hashable {
    var hashValue: Int { return dataParent.hashValue }
    
    fileprivate var fetchingCondition =  NSCondition()
    fileprivate var isFetching = false
    weak var dataCache: DataCache<T>?
    let dataParent: T
    
    init(_ dataParent: T,_ dataCache: DataCache<T>) {
        self.dataParent = dataParent
        self.dataCache = dataCache
    }
    
    static func == (lhs: DataWrapper, rhs: DataWrapper) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
    
    func invalidate() {
        dataCache?.parentWrapperDict.removeValue(forKey: dataParent)
    }
}

///Your generic FIFO linked list based queue
fileprivate class Queue<T: Equatable>
{
    ///Node for the linked list implementation of our queue
    private class Node<T> {
        let value: T
        var previous: Node<T>?
        weak var next: Node<T>?
        init(value: T) { self.value = value}
    }
    
    ///Front of our queue
    private var front: Node<T>?
    ///Back of our queue
    private var back: Node<T>?
    ///Size of our queue
    private var size: Int
    
    public init() {
        size = 0
    }
    
    ///Inserts the element: T into the queue
    public func enqueue(_ element: T) {
        if front == nil {
            front = Node<T>(value: element)
            back = front
        } else {
            back?.previous = Node<T>(value: element)
            back?.previous?.next = back
            back = back?.previous
        }
        size += 1
    }
    
    ///Pops the next element from the queue
    ///- returns: nil if empty, else front of the queue
    func getFront() -> T? {
        if size == 0 {return nil}
        let element = front
        
        if size == 1 {
            back = nil
            front = nil
        }
        else {
            front = front?.previous
            front?.next = nil
        }
        
        size -= 1
        
        return element?.value
    }
    
    ///Gets the size of the queue.
    /// - returns: Size of the queue
    func count() -> Int {
        return size
    }
    
    func print() {
        var temp = front
        Swift.print("Front: ", separator: "", terminator: "")
        while temp != nil {
            Swift.print(String(describing: temp!.value) + " <-> ", separator: "", terminator: "")
            temp = temp?.previous
        }
        Swift.print(" :Back")
    }
    
    func remove(element: T) {
        var temp = front
        while temp != nil {
            if temp!.value == element {
                if size == 1 {
                    back = nil
                    front = nil
                } else {
                    temp?.next?.previous = temp?.previous
                    temp?.previous?.next = temp?.next
                    
                    if temp?.value == back?.value {
                        back = temp?.next
                    }
                    if temp?.value == front?.value {
                        front = temp?.previous
                    }
                }
                size -= 1
                return
            } else {
                temp = temp?.previous
            }
        }
    }
}
