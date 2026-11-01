import Testing

extension Tag {
    /// Long end-to-end runs (full-size scrolling pages): skipped by `make test`, run nightly and
    /// before a release by `make test-slow` (#140). Slow suites are named `…SlowTests`.
    @Tag static var slow: Self
}
