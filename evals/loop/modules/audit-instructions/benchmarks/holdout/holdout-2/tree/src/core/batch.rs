pub const MAX_BATCH: usize = 10_000;

pub fn chunk(spans: Vec<String>) -> Vec<Vec<String>> {
    spans.chunks(MAX_BATCH).map(|c| c.to_vec()).collect()
}
