protocol Persisting {
    /// @lint.effect idempotent
    func persist()
}

/// The requirement annotates `persist()`, which shadows this body.
struct Draft: Persisting {
    let text: String
    let archive: Archive

    func persist() {
        archive.upsert(text)
    }
}

/// The attribute and the doc comment disagree.
/// @lint.effect idempotent
@NonIdempotent
func enqueueJob(_ jobs: JobQueue) {
    jobs.append(1)
}

/// The attribute and the doc comment agree.
/// @lint.effect idempotent
@Idempotent
func resetCounter(_ counter: Counter) {
    counter.reset()
}

@EffectUnknown
func mystery() -> Int {
    4
}

@ClockDeterministic
func ticks() -> Int {
    1
}

@ExternallyIdempotent(by: "requestID")
func charge(requestID: String, amount: Int, gateway: Gateway) {
    gateway.send(amount)
}

#if os(macOS)
func platformName() -> String {
    "macOS"
}
#else
func platformName() -> String {
    "other"
}
#endif
