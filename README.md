# SwiftyNetworkedDataCache
Easily cache and fetch data in one request. Cache will maintain the max size you set according to FIFO order, and trim the oldest items in the cache after the maximum size is reached.

### Why is this useful?
I created this to be able to keep a cache of profile images. It minimizes the effort required to maintain a capped size cache of user images, perfect for fetching many profile photos without having to worry about refetching the same data, or caching too many objects at once.

### How does it work?
Simply implement the CachedDataParent protocol to provide where to find the data, and use the fetchData method on an instance of DataCache, and it does the rest of the work for you. You get back a enum response telling you if and how the data was retrieved (from the network, cache, or if the network request outright failed).

### Sounds cool! Show me an example!!

    class User: CachedDataOwner {
        typealias ProcessedData = UIImage

        var hashValue: Int { return id }
        let id: Int
        var urlPath: String

        init(id: Int, urlPath: String) {
            self.id = id
            self.urlPath = urlPath
        }

        static func == (lhs: User, rhs: User) -> Bool {
            return lhs.id == rhs.id
        }

        static func processData(data: Data) -> UIImage? {
            return UIImage(data: data)
        }
    }

    let imageCache = DataCache<User>(maxSize: 20)
    let user = User(id: 1, urlPath: "https://httpbin.org/image/png")

    imageCache.fetchData(forParent: user) { (image, result) in
        print(image != nil, result)
        //true FETCHED
        imageCache.fetchData(forParent: user) { (image, result) in
            print(image != nil, result)
            //true CACHED
        }
    }
Just check out the example project to try it out!

