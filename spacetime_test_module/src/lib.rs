use spacetimedb::{
    procedure, reducer, table, view, AnonymousViewContext, ProcedureContext, ReducerContext, Table,
};

/// Simple Note table for testing
#[table(name = note, public)]
pub struct Note {
    #[primary_key]
    pub id: u32,
    pub title: String,
    pub content: String,
    #[index(btree)]
    pub timestamp: u64,
}

/// Reducer to create a new note
#[reducer]
pub fn create_note(ctx: &ReducerContext, title: String, content: String) {
    let id = ctx.db.note().count() as u32 + 1;
    let timestamp = 0;

    ctx.db.note().insert(Note {
        id,
        title,
        content,
        timestamp,
    });
}

#[reducer]
pub fn update_note(ctx: &ReducerContext, note_id: u32, title: String, content: String) {
    if let Some(mut note) = ctx.db.note().id().find(note_id) {
        note.title = title;
        note.content = content;
        note.timestamp = 0;
        ctx.db.note().id().update(note);
    }
}

#[reducer]
pub fn delete_note(ctx: &ReducerContext, note_id: u32) {
    ctx.db.note().id().delete(note_id);
}

/// Procedure to add two numbers (stateless computation)
#[procedure]
pub fn add_numbers(_ctx: &mut ProcedureContext, a: u32, b: u32) -> u32 {
    a + b
}

/// Procedure that always fails with an error (for testing error handling)
#[procedure]
pub fn divide_by_zero(_ctx: &mut ProcedureContext, numerator: u32) -> u32 {
    // Use a runtime value to prevent compile-time detection
    let divisor = if numerator > 0 { 0 } else { 1 };
    numerator / divisor // Will panic at runtime when numerator > 0
}

/// Procedure with expensive computation (for testing outOfEnergy - if applicable)
#[procedure]
pub fn expensive_computation(_ctx: &mut ProcedureContext, iterations: u32) -> u32 {
    let mut result = 0u32;
    for i in 0..iterations {
        result = result.wrapping_add(i);
    }
    result
}

/// View to get all notes
/// Uses the btree-indexed timestamp column to iterate all rows
#[view(name = all_notes, public)]
pub fn all_notes(ctx: &AnonymousViewContext) -> Vec<Note> {
    // Use the timestamp btree index with a range filter to get all notes
    ctx.db.note().timestamp().filter(0u64..).collect()
}

/// View to get first note (returns Option<Note>)
#[view(name = first_note, public)]
pub fn first_note(ctx: &AnonymousViewContext) -> Option<Note> {
    // Use the id index to find the first note
    ctx.db.note().id().find(1)
}

/// Initialize with some test data
#[reducer(init)]
pub fn init(ctx: &ReducerContext) {
    ctx.db.note().insert(Note {
        id: 1,
        title: "First Note".to_string(),
        content: "This is my first note".to_string(),
        timestamp: 0,
    });

    ctx.db.note().insert(Note {
        id: 2,
        title: "Second Note".to_string(),
        content: "This is my second note".to_string(),
        timestamp: 0,
    });
}
