///Your generic FIFO linked list based queue
fileprivate class Queue<T>
{
    ///Node for the linked list implementation of our queue
    private class Node<T> {
        var value: T
        var previous: Node<T>?
        init(value: T) { self.value = value }
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
    public func insert(_ element: T) {
        
        if front == nil {
            front = Node<T>(value: element)
            back = front
        } else {
            back?.previous = Node<T>(value: element)
            back = back?.previous
        }
        
        size += 1
    }
    
    ///Pops the next element from the queue
    ///- returns: nil if empty, else front of the queue
    func getFront() -> T? {
        let element = front
        
        if size == 1 {
            back = nil
            front = nil
        }
        else { front = front?.previous }
        
        if size > 0 { size -= 1 }
        
        return element?.value
    }
    
    ///Gets the size of the queue.
    /// - returns: Size of the queue
    public func getSize() -> Int {
        return size
    }
}

open class CachedValueParent<V>: Hashable {
    
    open var hashValue: Int { get { return id } }
    
    open let id: Int
    
    ///For internal use only
    fileprivate var fetchingCondition =  NSCondition()
    fileprivate var isFetching = false
    
    ///Url path for fetching data with a URLSession.dataTask
    fileprivate var urlPath: String?
    ///Called when the cache is about to invalidate this object
    open func willInvalidate() {}
    
    ///Required init for proper usage of cache
    ///- parameter id: unique identifier to use in hashing function
    required public init (id: Int, urlPath: String?) {
        self.id = id
        self.urlPath = urlPath
    }
    
    public static func == (lhs: CachedValueParent, rhs: CachedValueParent) -> Bool {
        return lhs.id == rhs.id
    }
    
    ///Used to update the urlPath
    open var getSetUrlPath: String? {
        get { return urlPath }
        set(newPath) { self.urlPath = newPath }
    }
    
    ///Process the data received from the network request
    open func processData(data: Data) -> V? {
        return nil
    }
}

///Caps cached items at a certain value. Inserting an element in a full cache
///will trim one element from the cache in FIFO order
fileprivate class CappedCache<K: CachedValueParent<V>, V> {
    
    private var cache: [K:V] = [:]
    private var maxSize: Int
    private var queue = Queue<K>()
    
    init(maxSize: Int = 25) {
        self.maxSize = maxSize
    }
    
    ///Sets the element for the value and trims the cache if necessary
    func set(_ key: K,_ value: V) {
        if queue.getSize() == maxSize {
            let expiredKey = queue.getFront()!
            expiredKey.willInvalidate()
            cache.removeValue(forKey: expiredKey)
        }
        queue.insert(key)
        cache[key] = value
    }
    
    ///Gets the element for the value in the cache if
    ///the element exists
    func get(_ key: K) -> V? {
        return cache[key]
    }
    
    ///Updates the max size and trims the cache if necessary
    func updateMaxSize(maxSize: Int) {
        self.maxSize = maxSize
        while queue.getSize() > maxSize {
            let expiredKey = queue.getFront()!
            expiredKey.willInvalidate()
            cache.removeValue(forKey: expiredKey)
        }
    }
}

enum CacheFetchResult {
    case CACHED, FETCHED, NILPATH, BADREQUEST, DATAPROCESSINGISSUE
}

///Used to limit the size of the data cache
///while minimizing the number of network requests
open class DataCache<V> {
    private var dataCache: CappedCache<CachedValueParent<V>,V>
    
    init(maxSize: Int) {
        self.dataCache = CappedCache<CachedValueParent<V>, V>(maxSize: maxSize)
    }
    
    ///Returns the profile photo if available.
    /// - parameter parent: parent object to fetch data for
    /// - parameter completion: NOT GUARANTEED TO RUN ON MAIN THREAD
    func fetchData(forParent parent: CachedValueParent<V>, _ completion: @escaping (V?, CacheFetchResult) -> Void) {
        parent.fetchingCondition.lock()
        
        if let object = dataCache.get(parent) {
            parent.fetchingCondition.unlock()
            completion(object, .CACHED)
        }
        else if parent.isFetching {
            parent.fetchingCondition.unlock()
            Thread {
                parent.fetchingCondition.lock()
                
                while parent.isFetching { parent.fetchingCondition.wait() }
                
                parent.fetchingCondition.unlock()
                completion(self.dataCache.get(parent), .CACHED)
                }.start()
        }
        else if let path = parent.urlPath {
            parent.isFetching = true
            parent.fetchingCondition.unlock()
            
            URLSession.shared.dataTask(with: URL(string: path)!) { (data, response, error) in
                parent.fetchingCondition.lock()
                
                var completionObject: V?
                var result: CacheFetchResult = .BADREQUEST
                
                defer {
                    parent.fetchingCondition.broadcast()
                    parent.fetchingCondition.unlock()
                    completion(completionObject, result)
                }
                
                //test for successful network request
                if let data = data,
                    error == nil,
                    [200,204].contains((response as? HTTPURLResponse)?.statusCode)
                {
                    completionObject = parent.processData(data: data)
                    if completionObject != nil {
                        result = .FETCHED
                        self.dataCache.set(parent, completionObject!)
                    }
                    else {
                        result = .DATAPROCESSINGISSUE
                    }
                    parent.isFetching = false
                }
                
                
                }.resume()
        }
        else {
            parent.fetchingCondition.unlock()
            completion(nil, .NILPATH)
        }
    }
}
