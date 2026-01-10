import CoreGraphics

struct MergeOffsetCompensator {
    static func compensation(
        previousOffset: CGFloat,
        currentOffset: CGFloat,
        threshold: CGFloat = 0.5
    ) -> CGFloat {
        let delta = previousOffset - currentOffset
        return abs(delta) > threshold ? delta : 0
    }
}

