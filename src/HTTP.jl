__precompile__()
module HTTP

using MbedTLS
import MbedTLS.SSLContext


const DEBUG_LEVEL = 1
const minimal = false

include("compat.jl")

include("debug.jl")
include("Pairs.jl")
include("Strings.jl")
include("IOExtras.jl")
include("uri.jl");                      using .URIs
                                                                     if !minimal
include("consts.jl")
include("utils.jl")
include("fifobuffer.jl");               using .FIFOBuffers
include("cookies.jl");                  using .Cookies
include("multipart.jl")
                                                                             end
include("parser.jl");                   import .Parsers: ParsingError, Headers
include("Connect.jl")
include("ConnectionPool.jl")
include("Messages.jl");                 using .Messages
                                        import .Messages: header, hasheader
include("Streams.jl");                  using .Streams
include("WebSockets.jl");               using .WebSockets


"""

    HTTP.request(method, url [, headers [, body]]; <keyword arguments>]) -> HTTP.Response

Send a HTTP Request Message and recieve a HTTP Response Message.

```
r = HTTP.request("GET", "http://httpbin.org/ip")
println(r.status)
println(String(r.body))
```

`headers` can be any collection where
`[string(k) => string(v) for (k,v) in headers]` yields `Vector{Pair}`.
e.g. a `Dict()`, a `Vector{Tuple}`, a `Vector{Pair}` or an iterator.

`body` can take a number of forms:

 - a `String`, a `Vector{UInt8}` or a readable `IO` stream
   or any `T` accepted by `write(::IO, ::T)`
 - a collection of `String` or `AbstractVector{UInt8}` or `IO` streams
   or items of any type `T` accepted by `write(::IO, ::T...)`
 - a readable `IO` stream or any `IO`-like type `T` for which
   `eof(T)` and `readavailable(T)` are defined.

The `HTTP.Response` struct contains:

 - `status::Int16` e.g. `200`
 - `headers::Vector{Pair{String,String}}`
    e.g. ["Server" => "Apache", "Content-Type" => "text/html"]
 - `body::Vector{UInt8}`, the Response Body bytes.
    Empty if a `response_stream` was specified in the `request`.

`HTTP.get`, `HTTP.put`, `HTTP.post` and `HTTP.head` are defined as shorthand
for `HTTP.request("GET", ...)`, etc.

`HTTP.request` and `HTTP.open` also accept the following optional keyword
parameters:


Streaming options (See [`HTTP.StreamLayer`](@ref)])

 - `response_stream = nothing`, a writeable `IO` stream or any `IO`-like
    type `T` for which `write(T, AbstractVector{UInt8})` is defined.
 - `verbose = 0`, set to `1` or `2` for extra message logging.


Connection Pool options (See `ConnectionPool.jl`)

 - `connectionpool = true`, enable the `ConnectionPool`.
 - `duplicate_limit = 7`, number of duplicate connections to each host:port.
 - `pipeline_limit = 16`, number of simultaneous requests per connection.
 - `reuse_limit = nolimit`, each connection is closed after this many requests.
 - `socket_type = TCPSocket`


Timeout options (See [`HTTP.TimeoutLayer`](@ref)])

 - `timeout = 60`, close the connection if no data is recieved for this many
   seconds. Use `timeout = 0` to disable.


Retry options (See [`HTTP.RetryLayer`](@ref)])

 - `retry = true`, retry idempotent requests in case of error.
 - `retries = 4`, number of times to retry.
 - `retry_non_idempotent = false`, retry non-idempotent requests too. e.g. POST.


Redirect options (See [`HTTP.RedirectLayer`](@ref)])

 - `redirect = true`, follow 3xx redirect responses.
 - `redirect_limit = 3`, number of times to redirect.
 - `forwardheaders = false`, forward original headers on redirect.


Status Exception options (See [`HTTP.ExceptionLayer`](@ref)])

 - `statusexception = true`, throw `HTTP.StatusError` for response status >= 300.


SSLContext options (See `Connect.jl`)

 - `require_ssl_verification = false`, pass `MBEDTLS_SSL_VERIFY_REQUIRED` to
   the mbed TLS library.
   ["... peer must present a valid certificate, handshake is aborted if
     verification failed."](https://tls.mbed.org/api/ssl_8h.html#a5695285c9dbfefec295012b566290f37)
 - sslconfig = SSLConfig(require_ssl_verification)`


Basic Authenticaiton options (See [`HTTP.BasicAuthLayer`](@ref)])

 - basicauthorization=false, add `Authorization: Basic` header using credentials
   from url userinfo.


AWS Authenticaiton options (See [`HTTP.AWS4AuthLayer`](@ref)])
 - `awsauthorization = false`, enable AWS4 Authentication.
 - `aws_service = split(uri.host, ".")[1]`
 - `aws_region = split(uri.host, ".")[2]`
 - `aws_access_key_id = ENV["AWS_ACCESS_KEY_ID"]`
 - `aws_secret_access_key = ENV["AWS_SECRET_ACCESS_KEY"]`
 - `aws_session_token = get(ENV, "AWS_SESSION_TOKEN", "")`
 - `body_sha256 = digest(MD_SHA256, body)`,
 - `body_md5 = digest(MD_MD5, body)`,


Cookie options (See [`HTTP.CookieLayer`](@ref)])

 - `cookies = false`, enable cookies.
 - `cookiejar::Dict{String, Set{Cookie}}=default_cookiejar`


Cananoincalization options (See [`HTTP.CanonicalizeLayer`](@ref)])

 - `canonicalizeheaders = false`, rewrite request and response headers in
   Canonical-Camel-Dash-Format.


## Request Body Examples

String body:
```
r = request("POST", "http://httpbin.org/post", [], "post body data")
@show r.status
```

Stream body from file:
```
io = open("post_data.txt", "r")
r = request("POST", "http://httpbin.org/post", [], io)
@show r.status
```

Generator body:
```
chunks = ("chunk\$i" for i in 1:1000)
r = request("POST", "http://httpbin.org/post", [], chunks)
@show r.status
```

Collection body:
```
chunks = [preamble_chunk, data_chunk, checksum(data_chunk)]
r = request("POST", "http://httpbin.org/post", [], chunks)
@show r.status
```

`open() do io` body:
```
r = HTTP.open("POST", "http://httpbin.org/post") do io
    write(io, preamble_chunk)
    write(io, data_chunk)
    write(io, checksum(data_chunk))
end
@show r.status
```


## Response Body Examples

String body:
```
r = request("GET", "http://httpbin.org/get")
@show r.status
println(String(r.body))
```

Stream body to file:
```
io = open("get_data.txt", "w")
r = request("GET", "http://httpbin.org/get", response_stream=io)
@show r.status
println(read("get_data.txt"))
```

Stream body through buffer:
```
io = BufferStream()
@async while !eof(io)
    bytes = readavailable(io))
    println("GET data: \$bytes")
end
r = request("GET", "http://httpbin.org/get", response_stream=io)
@show r.status
```

Stream body through `open() do io`:
```
r = HTTP.open("GET", "http://httpbin.org/get") do io
    r = startread(io)
    @show r.status
    while !eof(io)
        bytes = readavailable(io))
        println("GET data: \$bytes")
    end
end
```


## Request and Response Body Examples

String bodies:
```
r = request("POST", "http://httpbin.org/post", [], "post body data")
@show r.status
println(String(r.body))
```

Stream bodies from and to files:
```
in = open("foo.png", "r")
out = open("foo.jpg", "w")
r = request("POST", "http://convert.com/png2jpg", [], in, response_stream=out)
@show r.status
```

Stream bodies through: `open() do io`:
```
HTTP.open("POST", "http://music.com/play") do io
    write(io, JSON.json([
        "auth" => "12345XXXX",
        "song_id" => 7,
    ]))
    r = readresponse(io)
    @show r.status
    while !eof(io)
        bytes = readavailable(io))
        play_audio(bytes)
    end
end
```
"""

request(method::String, uri::URI, headers::Headers, body; kw...)::Response =
    request(HTTP.stack(;kw...), method, uri, headers, body; kw...)

request(method, uri, headers=[], body=UInt8[]; kw...)::Response =
    request(string(method), URI(uri), mkheaders(headers), body; kw...)


"""
    HTTP.open(method, url, [,headers]) do
        write(io, bytes)
    end -> HTTP.Response

The `HTTP.open` API allows the Request Body to be written to an `IO` stream.
`HTTP.open` also allows the Response Body to be streamed:


    HTTP.open(method, url, [,headers]) do io
        [startread(io) -> HTTP.Response]
        while !eof(io)
            readavailable(io) -> AbstractVector{UInt8}
        end
    end -> HTTP.Response
"""

open(f::Function, method::String, uri, headers=[]; kw...)::Response =
    request(method, uri, headers, nothing; iofunction=f, kw...)


"""
    HTTP.get(url [, headers]; <keyword arguments>) -> HTTP.Response


Shorthand for `HTTP.request("GET", ...)`. See [`HTTP.request`](@ref).
"""


get(a...; kw...) = request("GET", a..., kw...)

"""
    HTTP.put(url, headers, body; <keyword arguments>) -> HTTP.Response

Shorthand for `HTTP.request("PUT", ...)`. See [`HTTP.request`](@ref).
"""


put(a...; kw...) = request("PUT", a..., kw...)

"""
    HTTP.post(url, headers, body; <keyword arguments>) -> HTTP.Response

Shorthand for `HTTP.request("POST", ...)`. See [`HTTP.request`](@ref).
"""


post(a...; kw...) = request("POST", a..., kw...)

"""
    HTTP.head(url; <keyword arguments>) -> HTTP.Response

Shorthand for `HTTP.request("HEAD", ...)`. See [`HTTP.request`](@ref).
"""

head(a...; kw...) = request("HEAD", a..., kw...)



"""

## Request Execution Stack

The Request Execution Stack is separated into composable layers.

Each layer is defined by a nested type `Layer{Next}` where the `Next`
parameter defines the next layer in the stack.
The `request` method for each layer takes a `Layer{Next}` type as
its first argument and dispatches the request to the next layer
using `request(Next, ...)`.

The example below defines three layers and three stacks each with
a different combination of layers.


```julia
abstract type Layer end
abstract type Layer1{Next <: Layer} <: Layer end
abstract type Layer2{Next <: Layer} <: Layer end
abstract type Layer3 <: Layer end

request(::Type{Layer1{Next}}, data) where Next = "L1", request(Next, data)
request(::Type{Layer2{Next}}, data) where Next = "L2", request(Next, data)
request(::Type{Layer3}, data) = "L3", data

const stack1 = Layer1{Layer2{Layer3}}
const stack2 = Layer2{Layer1{Layer3}}
const stack3 = Layer1{Layer3}
```

```julia
julia> request(stack1, "foo")
("L1", ("L2", ("L3", "foo")))

julia> request(stack2, "bar")
("L2", ("L1", ("L3", "bar")))

julia> request(stack3, "boo")
("L1", ("L3", "boo"))
```

This stack definition pattern gives the user flexibility in how layers are
combined but still allows Julia to do whole-stack comiple time optimistations.

e.g. the `request(stack1, "foo")` call above is optimised down to a single
function:
```julia
julia> code_typed(request, (Type{stack1}, String))[1].first
CodeInfo(:(begin
    return (Core.tuple)("L1", (Core.tuple)("L2", (Core.tuple)("L3", data)))
end))
```
"""

abstract type Layer end
                                                                     if !minimal
include("RedirectRequest.jl");          using .RedirectRequest
include("BasicAuthRequest.jl");         using .BasicAuthRequest
include("AWS4AuthRequest.jl");          using .AWS4AuthRequest
include("CookieRequest.jl");            using .CookieRequest
include("CanonicalizeRequest.jl");      using .CanonicalizeRequest
include("TimeoutRequest.jl");           using .TimeoutRequest
                                                                             end
include("MessageRequest.jl");           using .MessageRequest
include("ExceptionRequest.jl");         using .ExceptionRequest
                                        import .ExceptionRequest.StatusError
include("RetryRequest.jl");             using .RetryRequest
include("ConnectionRequest.jl");        using .ConnectionRequest
include("StreamRequest.jl");            using .StreamRequest

"""
The `stack()` function returns the default HTTP Layer-stack type.
This type is passed as the first parameter to the [`HTTP.request`](@ref) function.

`stack()` accepts optional keyword arguments to enable/disable specific layers
in the stack:
`request(method, args...; kw...) request(stack(;kw...), args...; kw...)`


The minimal request execution stack is:

```
stack = MessageLayer{ConnectionPoolLayer{StreamLayer}}
```

The figure below illustrates a minimal Layer-stack with the
`connectionpool=false` option that causes the `ConnectionPoolLayer` to call
HTTP.Connect.getconnection() directly rather reusing pooled connections.

```
 ┌────────────────────────────────────────────────────────────────────────────┐
 │                                            ┌───────────────────┐           │
 │     request(method, uri, headers, body) -> │ HTTP.Response     │           │
 │             ──────────────────────────     └─────────▲─────────┘           │
 │                           ║                          ║                     │
 │   ┌────────────────────────────────────────────────────────────┐           │
 │   │ request(MessageLayer,      method, ::URI, ::Headers, body) │           │
 │   ├────────────────────────────────────────────────────────────┤           │
┌┼───┤ request(ConnectionPoolLayer,       ::URI, ::Request, body) │           │
││   ├────────────────────────────────────────────────────────────┤           │
││   │ request(StreamLayer,               ::IO,  ::Request, body) │           │
││   └──────────────┬───────────────────┬─────────────────────────┘           │
│└──────────────────┼────────║──────────┼───────────────║─────────────────────┘
│                   │        ║          │               ║                      
│┌──────────────────▼───────────────┐   │  ┌──────────────────────────────────┐
││ HTTP.Request                     │   │  │ HTTP.Response                    │
│└──────────────────▲───────────────┘   │  └───────────────▲──────────────────┘
│┌──────────────────┴────────║──────────▼───────────────║──┴──────────────────┐
││ HTTP.Stream <:IO          ║           ╔══════╗       ║                     │
│└───────────────────────────║───────────║──────║───────║──┬──────────────────┘
│┌──────────────────────────────────┐    ║ ┌────▼───────║──▼──────────────────┐
││ HTTP.Messages                    │    ║ │ HTTP.Parser                      │
│└──────────────────────────────────┘    ║ └──────────────────────────────────┘
│┌───────────────────────────║───────────║────────────────────────────────────┐
└▶ HTTP.Connect              ║           ║                                    │
 └───────────────────────────║───────────║────────────────────────────────────┘
                             ║           ║                                     
 ┌───────────────────────────║───────────║──────────────┐  ┏━━━━━━━━━━━━━━━━━━┓
 │ HTTP Server               ▼           ║              │  ┃ data flow: ════▶ ┃
 │                        Request     Response          │  ┃ reference: ────▶ ┃
 └──────────────────────────────────────────────────────┘  ┗━━━━━━━━━━━━━━━━━━┛
```

The next figure illustrates the full Layer-stack and its relationship with
the [`HTTP.Response`](@ref), the [`HTTP.Parser`](@ref),
the [`HTTP.Stream`](@ref) and the [`HTTP.ConnectionPool`](@ref).

```
 ┌────────────────────────────────────────────────────────────────────────────┐
 │                                                       ┌──────────────────┐ │
 │  HTTP.jl Request Stack                                │ HTTP.StatusError │ │
 │                                                       └───────────┬──────┘ │
 │                                            ┌───────────────────┐           │
 │     request(method, uri, headers, body) -> │ HTTP.Response     │  │        │
 │             ──────────────────────────     └─────────▲─────────┘           │
 │                           ║                          ║            │        │
 │   ┌────────────────────────────────────────────────────────────┐           │
 │   │ request(RedirectLayer,     method, ::URI, ::Headers, body) │  │        │
 │   ├────────────────────────────────────────────────────────────┤           │
 │   │ request(BasicAuthLayer,    method, ::URI, ::Headers, body) │  │        │
 │   ├────────────────────────────────────────────────────────────┤           │
 │   │ request(CookieLayer,       method, ::URI, ::Headers, body) │  │        │
 │   ├────────────────────────────────────────────────────────────┤           │
 │   │ request(CanonicalizeLayer, method, ::URI, ::Headers, body) │  │        │
 │   ├────────────────────────────────────────────────────────────┤           │
 │   │ request(MessageLayer,      method, ::URI, ::Headers, body) │  │        │
 │   ├────────────────────────────────────────────────────────────┤           │
 │   │ request(AWS4AuthLayer,             ::URI, ::Request, body) │  │        │
 │   ├────────────────────────────────────────────────────────────┤           │
 │   │ request(RetryLayer,                ::URI, ::Request, body) │  │        │
 │   ├────────────────────────────────────────────────────────────┤           │
 │   │ request(ExceptionLayer,            ::URI, ::Request, body) │─ ┘        │
 │   ├────────────────────────────────────────────────────────────┤           │
┌┼───┤ request(ConnectionPoolLayer,       ::URI, ::Request, body) │           │
││   ├────────────────────────────────────────────────────────────┤           │
││   │ request(TimeoutLayer,              ::IO,  ::Request, body) │           │
││   ├────────────────────────────────────────────────────────────┤           │
││   │ request(StreamLayer,               ::IO,  ::Request, body) │           │
││   └──────────────┬───────────────────┬─────────────────────────┘           │
│└──────────────────┼────────║──────────┼───────────────║─────────────────────┘
│                   │        ║          │               ║                      
│┌──────────────────▼───────────────┐   │  ┌──────────────────────────────────┐
││ HTTP.Request                     │   │  │ HTTP.Response                    │
││                                  │   │  │                                  │
││ method::String                   ◀───┼──▶ status::Int                      │
││ uri::String                      │   │  │ headers::Vector{Pair}            │
││ headers::Vector{Pair}            │   │  │ body::Vector{UInt8}              │
││ body::Vector{UInt8}              │   │  │                                  │
│└──────────────────▲───────────────┘   │  └───────────────▲──────────────────┘
│┌──────────────────┴────────║──────────▼───────────────║──┴──────────────────┐
││ HTTP.Stream <:IO          ║           ╔══════╗       ║                     │
││   ┌───────────────────────────┐       ║   ┌──▼─────────────────────────┐   │
││   │ startwrite(::Stream)      │       ║   │ startread(::Stream)        │   │
││   │ write(::Stream, body)     │       ║   │ read(::Stream) -> body     │   │
││   │ ...                       │       ║   │ ...                        │   │
││   │ closewrite(::Stream)      │       ║   │ closeread(::Stream)        │   │
││   └───────────────────────────┘       ║   └────────────────────────────┘   │
││ EOFError <:Exception      ║           ║      ║       ║                     │
│└───────────────────────────║────────┬──║──────║───────║──┬──────────────────┘
│┌──────────────────────────────────┐ │  ║ ┌────▼───────║──▼──────────────────┐
││ HTTP.Messages                    │ │  ║ │ HTTP.Parser                      │
││                                  │ │  ║ │                                  │
││ writestartline(::IO, ::Request)  │ │  ║ │ parseheaders(bytes) do h::Pair   │
││ writeheaders(::IO, ::Request)    │ │  ║ │ parsebody(bytes) -> bytes        │
││                                  │ │  ║ │                                  │
││                                  │ │  ║ │ ParsingError <:Exception         │
│└──────────────────────────────────┘ │  ║ └──────────────────────────────────┘
│                            ║        │  ║                                     
│┌───────────────────────────║────────┼──║────────────────────────────────────┐
└▶ HTTP.ConnectionPool       ║        │  ║                                    │
 │                     ┌──────────────▼────────┐ ┌───────────────────────┐    │
 │ getconnection() ->  │ HTTP.Transaction <:IO │ │ HTTP.Transaction <:IO │    │
 │       │             └───────────────────────┘ └───────────────────────┘    │
 │       │                   ║    ╲│╱    ║                  ╲│╱               │
 │       │                   ║     │     ║                   │                │
 │       │             ┌───────────▼───────────┐ ┌───────────▼───────────┐    │
 │       │      pool: [│ HTTP.Connection       │,│ HTTP.Connection       │...]│
 │       │             └───────────┬───────────┘ └───────────┬───────────┘    │
 └───────┼───────────────────║─────┼─────║───────────────────┼────────────────┘
 ┌───────▼───────────────────║─────┼─────║───────────────────┼────────────────┐
 │ HTTP.Connect              ║     │     ║                   │                │
 │                     ┌───────────▼───────────┐ ┌───────────▼───────────┐    │
 │ getconnection() ->  │ Base.TCPSocket <:IO   │ │MbedTLS.SSLContext <:IO│    │
 │                     └───────────────────────┘ └───────────┬───────────┘    │
 │                           ║           ║                   │                │
 │ EOFError <:Exception      ║           ║       ┌───────────▼───────────┐    │
 │ UVError <:Exception       ║           ║       │ Base.TCPSocket <:IO   │    │
 │ DNSError <:Exception      ║           ║       └───────────────────────┘    │
 └───────────────────────────║───────────║────────────────────────────────────┘
                             ║           ║                                     
 ┌───────────────────────────║───────────║──────────────┐  ┏━━━━━━━━━━━━━━━━━━┓
 │ HTTP Server               ▼           ║              │  ┃ data flow: ════▶ ┃
 │                        Request     Response          │  ┃ reference: ────▶ ┃
 └──────────────────────────────────────────────────────┘  ┗━━━━━━━━━━━━━━━━━━┛
```
*See `docs/src/layers`[`.monopic`](http://monodraw.helftone.com).*
"""

function stack(;redirect=true,
                basicauthorization=false,
                awsauthorization=false,
                cookies=false,
                canonicalizeheaders=false,
                retry=true,
                statusexception=true,
                timeout=0,
                kw...)
                                                                      if minimal
    MessageLayer{ExceptionLayer{ConnectionPoolLayer{StreamLayer}}}
                                                                            else
    NoLayer = Union

    (redirect            ? RedirectLayer       : NoLayer){
    (basicauthorization  ? BasicAuthLayer      : NoLayer){
    (cookies             ? CookieLayer         : NoLayer){
    (canonicalizeheaders ? CanonicalizeLayer   : NoLayer){
                           MessageLayer{
    (awsauthorization    ? AWS4AuthLayer       : NoLayer){
    (retry               ? RetryLayer          : NoLayer){
    (statusexception     ? ExceptionLayer      : NoLayer){
                           ConnectionPoolLayer{
    (timeout > 0         ? TimeoutLayer        : NoLayer){
                           StreamLayer
    }}}}}}}}}}
                                                                             end
end


                                                                     if !minimal
include("client.jl")
include("sniff.jl")
include("handlers.jl");                  using .Handlers
include("server.jl");                    using .Nitrogen
include("precompile.jl")
                                                                             end


end # module
