# WireMock Adapter for gRPC

[![Stability: Experimental](https://masterminds.github.io/stability/experimental.svg)](https://masterminds.github.io/stability/experimental.html)

> **DISCLAIMER:** This repository was forked from [Adven27/grpc-wiremock](https://github.com/Adven27/grpc-wiremock) which was archived by the maintainer.
> This fork is used to preserve the repository, and to make it available for experimental use and contributions.
> See [wiremock/wiremock #2148](https://github.com/wiremock/wiremock/issues/2148) for the feature request about providing an officially supported implementation
> (or updating this one)

_grpc-wiremock_ is a **mock server** for **GRPC** services implemented as a wrapper around the [WireMock](https://wiremock.org) HTTP server.
It is implementated in Java and runs as a standalone proxy container.

## How It Works

<p align="center">
  <img src="doc/overview.drawio.svg"/>
</p>

*grpc-wiremock* starts a gRPC server generated based on provided proto files which will convert a proto grpc request to JSON and redirects it as a POST request to the WireMock then converts a http response back to grpc proto format.
1. GRPC server works on `tcp://localhost:50000`
2. WireMock server works on `http://localhost:8888`

## Quick Start

### Run

```posh
docker run -p 8888:8888 -p 50000:50000 -v $(pwd)/example/proto:/proto -v $(pwd)/example/wiremock:/wiremock wiremock/grpc-wiremock
```

### Stub

```posh
curl -X POST http://localhost:8888/__admin/mappings \
  -d '{
    "request": {
        "method": "POST",
        "url": "/BalanceService/getUserBalance",
        "headers": {"withAmount": {"matches": "\\d+\\.?\\d*"} },
        "bodyPatterns" : [ {
            "equalToJson" : { "userId": "1", "currency": "EUR" }
        } ]
    },
    "response": {
        "status": 200,
        "jsonBody": { 
            "balance": { 
                "amount": { "value": { "decimal" : "{{request.headers.withAmount}}" }, "value_present": true },
                "currency": { "value": "EUR", "value_present": true }
            } 
        }
    }
}'
```

### Check

```posh
grpcurl -H 'withAmount: 100.0' -plaintext -d '{"user_id": 1, "currency": "EUR"}' localhost:50000 api.wallet.BalanceService/getUserBalance
```

Should get response:

```json
{
  "balance": {
    "amount": {
      "value": {
        "decimal": "100.0"
      },
      "value_present": true
    },
    "currency": {
      "value": "EUR",
      "value_present": true
    }
  }
}
```

## Stubbing

Stubbing should be done via [WireMock JSON API](http://wiremock.org/docs/stubbing/)

### Error mapping

Default error (not `200 OK`) mapping is based on https://github.com/googleapis/googleapis/blob/master/google/rpc/code.proto :

| HTTP Status Code          | GRPC Status        | 
|---------------------------|:-------------------|
| 400 Bad Request           | INVALID_ARGUMENT   |
| 401 Unauthorized          | UNAUTHENTICATED    |
| 403 Forbidden             | PERMISSION_DENIED  |
| 404 Not Found             | NOT_FOUND          |
| 409 Conflict              | ALREADY_EXISTS     |
| 429 Too Many Requests     | RESOURCE_EXHAUSTED |
| 499 Client Closed Request | CANCELLED          |
| 500 Internal Server Error | INTERNAL           |
| 501 Not Implemented       | UNIMPLEMENTED      |
| 503 Service Unavailable   | UNAVAILABLE        |
| 504 Gateway Timeout       | DEADLINE_EXCEEDED  |

And could be overridden or augmented by overriding or augmenting the following properties:

```yaml
grpc:
  error-code-by:
    http:
      status-code:
        400: INVALID_ARGUMENT
        401: UNAUTHENTICATED
        403: PERMISSION_DENIED
        404: NOT_FOUND
        409: ALREADY_EXISTS
        429: RESOURCE_EXHAUSTED
        499: CANCELLED
        500: INTERNAL
        501: UNIMPLEMENTED
        503: UNAVAILABLE
        504: DEADLINE_EXCEEDED
```

For example:

```posh
docker run \
    -e GRPC_ERRORCODEBY_HTTP_STATUSCODE_400=OUT_OF_RANGE \
    -e GRPC_ERRORCODEBY_HTTP_STATUSCODE_510=DATA_LOSS \
    wiremock/grpc-wiremock
```

## How To

### 1. Configure gRPC server

Currently, following grpc server properties are supported:

```properties
GRPC_SERVER_PORT
GRPC_SERVER_MAXHEADERLISTSIZE
GRPC_SERVER_MAXMESSAGESIZE
GRPC_SERVER_MAXINBOUNDMETADATASIZE
GRPC_SERVER_MAXINBOUNDMESSAGESIZE
```

Could be used like this:

```posh
docker run -e GRPC_SERVER_MAXHEADERLISTSIZE=1000 wiremock/grpc-wiremock
```

### 2. Configure WireMock server

WireMock server may be configured by passing [command line options](http://wiremock.org/docs/running-standalone/) 
prefixed by `wiremock_`:

```posh
docker run -e WIREMOCK_DISABLE-REQUEST-LOGGING -e WIREMOCK_PORT=0 wiremock/grpc-wiremock
```

### 3. Mock server-side streaming

Given the service:

```protobuf
service WalletService {
  rpc searchTransaction (SearchTransactionRequest) returns (stream SearchTransactionResponse) {}
}
```

Then the following stub may be provided, where `response.headers.streamSize` specifies
how many responses should be returned during the stream (`1` - if absent).

The current response iteration number is available in `request.headers.streamCursor`:

```posh
curl -X POST http://localhost:8888/__admin/mappings \
  -d '{
  "request": {
    "method": "POST",
    "url": "/WalletService/searchTransaction"
  },
  "response": {
    "fixedDelayMilliseconds": 1000,
    "headers": {"streamSize": "5" },
    "jsonBody": {
      "transactions": [
        {
          "id": "{{request.headers.streamCursor}}",
          "userId": "1",
          "currency": "EUR",
          "amount": {
            "decimal": "{{request.headers.streamCursor}}00"
          }
        },
        {
          "id": "100{{request.headers.streamCursor}}",
          "userId": "2",
          "currency": "EUR",
          "amount": {
            "decimal": "200"
          }
        }
      ]
    }
  }
}'
```

### 4. Speed up container start

In case you don't need to change proto files, you can build your own image with precompiled protos.  
See an [example](/example/Dockerfile)

### 5. Use with snappy compresser/decompresser

Snappy support can be enabled using `EXTERNAL_CODECS` env variable as follows:

```posh
docker run -e EXTERNAL_CODECS="snappy, another" wiremock/grpc-wiremock
```

Also in docker-compose:

```posh
    image: wiremock/grpc-wiremock
    ports:
      - "12085:50000" # grpc port
      - "8088:8888" # http serve port
    volumes:
      - ./example/proto:/proto
    environment:
      - EXTERNAL_CODECS=snappy
```

<sub>*gzip compression supported by default</sub>

### 6. Use in load testing

To increase performance some Wiremock related options may be tuned either directly or by enabling the "load" profile.
Next two commands are identical:

```posh
docker run -e SPRING_PROFILES_ACTIVE=load wiremock/grpc-wiremock
```

```posh
docker run \
  -e WIREMOCK_NO-REQUEST-JOURNAL \
  -e WIREMOCK_DISABLE-REQUEST-LOGGING \
  -e WIREMOCK_ASYNC-RESPONSE-ENABLED \
  -e WIREMOCK_ASYNC-RESPONSE-THREADS=10 \
  wiremock/grpc-wiremock
```

### 7. Preserving proto field names in stubs

By default, stub mappings must have proto fields references in lowerCamlCase, e.g. proto field `user_id` must be referenced as:

```json
{
  "request": {
    "method": "POST",
    "url": "/BalanceService/getUserBalance",
    "bodyPatterns": [{"equalToJson": { "userId": "1" }}]
  }
}
```

To preserve proto field names the following env variable could be used:

```posh
docker run -e JSON_PRESERVING_PROTO_FIELD_NAMES=true wiremock/grpc-wiremock
```
