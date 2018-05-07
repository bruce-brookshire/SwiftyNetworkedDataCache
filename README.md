# SwiftyNetworkedDataCache
Easily cache and fetch data in one request! Cache will maintain the max size you set according to FIFO order, and trim the oldest items in the cache after the maximum size is reached. Additionally, it prevents the same data from being double fetched (i.e. main thread asks for the same resource 2x before download finished, data is only fetched once. This operates like a waiter queue, calling completion with the result after waiter is finished). After all, who needs to fetch the same data twice? (This is dependent on data remaining in the cache. It is up to you to decided how large to make the cache. If you never want the cache to trim, set to Int.max)

### Why is this useful?
I created this to be able to keep a cache of profile images. It minimizes the effort required to maintain a capped size cache of data, perfect for fetching many profile photos without having to worry about refetching the same data, or caching too many objects at once.

But of course, you can use other data types too! It works for any datatype you have in mind :)

Additionally, this cache is not safe for concurrent mutations (you must lock the object before fetching on two or more threads).

### How does it work?
Simply implement the CachedDataParent protocol to provide where to find the data, and use the fetchData method on an instance of DataCache, and it does the rest of the work for you. You get back a enum response telling you if and how the data was retrieved (from the network, cache, or if the network request outright failed). The data from the network request is delivered to you via a static func so that you can even decode a json object and store it in the cache. Pretty simple, huh?

### Sounds cool! Show me an example!!
    // First we will implement a simple User object to act as the parent
    // for the data fetch.
    class User: CachedDataOwner {
    
        // This is the type of data you expect from the request
        typealias ProcessedData = UIImage
        
        // Here, we used a User id as the hashValue, but pick whatever you want
        var hashValue: Int { return id }
        let id: Int
        
        // This is the good part. This is where you store the url for the data fetch!
        var urlPath: String

        // Ya know, just good old OOP
        init(id: Int, urlPath: String) {
            self.id = id
            self.urlPath = urlPath
        }
        
        // Equatable. Thanks Apple for making Hashable require this.
        static func == (lhs: User, rhs: User) -> Bool {
            return lhs.id == rhs.id
        }
        
        // SUPER IMPORTANT: This is the way you process the server data how you like it
        // and return the ProccessedData type from up above. The return value is what gets cached
        static func processData(data: Data) -> ProcessedData? {
            return UIImage(data: data)
        }
    }
    
    // Lets make a User cache with a max size of 20.
    let imageCache = DataCache<User>(maxSize: 20)
    
    // Next lets make a user with a unique identifier through our User intializer, and 
    // give it a url to download an image from
    let user = User(id: 1, urlPath: "https://httpbin.org/image/png")

    // Finally, lets fetch the data. When it finishes, we will perform a second fetch
    // to show that the data has been cached appropriately
    imageCache.fetchData(forParent: user) { (image, result) in
        print(image != nil, result)
        // Output: true FETCHED
        
        imageCache.fetchData(forParent: user) { (image, result) in
            print(image != nil, result)
            // Output: true CACHED
        }
    }
    
Just check out the example project to try it out!

