FROM golang:1.26-trixie AS base-builder

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN apt-get update && apt-get install -y build-essential

ARG TARGETOS
ARG TARGETARCH
ARG METALBOND_VERSION

WORKDIR /build

COPY ironcore-dev-key-exchange/rust_mls_bridge/ ./rust_mls_bridge/
WORKDIR /build/rust_mls_bridge
RUN cargo build --release

WORKDIR /build/app
COPY . .

# Critical: CGO_ENABLED=1 is strictly required for Go plugins
ENV CGO_ENABLED=1
# ENV CGO_LDFLAGS="-L/build/rust_mls_bridge/target/release -lrust_mls_bridge -lm -ldl -lpthread"


FROM base-builder AS plugin-builder
WORKDIR /build/app

# IMPORTANT: -trimpath is ABSOLUTE necessary to that the metalbond binary accept the plugin
RUN CGO_ENABLED=1 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -buildvcs=false -ldflags "-X github.com/ironcore-dev/metalbond.METALBOND_VERSION=$METALBOND_VERSION"  -buildmode=plugin -o /build/server.so ironcore-dev-key-exchange/plugins/server/server.go
RUN CGO_ENABLED=1 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -buildvcs=false -ldflags "-X github.com/ironcore-dev/metalbond.METALBOND_VERSION=$METALBOND_VERSION"  -buildmode=plugin -o /build/client.so ironcore-dev-key-exchange/plugins/client/client.go





FROM golang:1.26-trixie AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG GOARCH=''

RUN apt-get update && apt-get install -y libpcap-dev

WORKDIR /workspace

# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum

# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    go mod download

COPY cmd cmd
COPY html html
COPY pb pb
COPY *.go ./
COPY ironcore-dev-key-exchange ironcore-dev-key-exchange

COPY extras/arp_spoofer arp_spoofer

ARG TARGETOS
ARG TARGETARCH

# Build MetalBond
ARG METALBOND_VERSION
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    CGO_ENABLED=1 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -buildvcs=false -ldflags "-X github.com/ironcore-dev/metalbond.METALBOND_VERSION=$METALBOND_VERSION" -o metalbond cmd/cmd.go

# Build ARP Spoofer
WORKDIR /workspace/arp_spoofer
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    CGO_ENABLED=1 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -buildvcs=false -ldflags "-X main.version=$METALBOND_VERSION" -o ../spoofer main.go

FROM debian:trixie-slim

RUN apt-get update && apt-get install -y iproute2 ethtool wget adduser inetutils-ping libpcap-dev && rm -rf /var/lib/apt/lists/*
COPY --from=builder /workspace/metalbond /usr/sbin/metalbond
COPY --from=builder /workspace/html /usr/share/metalbond/html
COPY --from=builder /workspace/spoofer /usr/sbin/spoofer
COPY --from=plugin-builder /build/server.so /plugins/server.so
COPY --from=plugin-builder /build/client.so /plugins/client.so

RUN mkdir -p /etc/iproute2 && echo -e "254\tmetalbond" >> "/etc/iproute2/rt_protos"
