# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-11-21

### Added

#### Core Features
- WebSocket connection management with automatic reconnection
- Connection state tracking and quality metrics
- SSL/TLS support with configurable certificates
- Brotli compression support for messages

#### BSATN Codec
- Complete BSATN binary encoding/decoding implementation
- Support for all SpacetimeDB types (integers, floats, strings, arrays, maps)
- Type-safe encoding with bounds checking

#### Table Cache
- Client-side table caching with automatic synchronization
- Row decoder system for typed table access
- Streaming updates for table changes (inserts, updates, deletes)

#### Reducers
- Type-safe reducer calling system
- Event-driven reducer responses
- Transaction support with commit tracking

#### Code Generation
- CLI tool for generating Dart client code from SpacetimeDB schemas
- Table class generation with typed fields
- Reducer method generation
- Sum type (Rust enum) support with sealed Dart classes
- View support (Vec, Option, single-row)

#### Authentication
- Identity and token management
- OIDC authentication support
- Pluggable token storage (in-memory and persistent)

#### Events
- Event stream system for real-time updates
- Transaction events with energy tracking
- Error event handling

### Infrastructure
- Comprehensive test suite (170+ tests)
- Unit and integration test separation
- Automated test environment setup

## [Unreleased]


