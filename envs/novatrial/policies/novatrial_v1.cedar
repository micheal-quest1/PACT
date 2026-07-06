// =============================================================================
// NovaTrial CRO — Cedar Policy v1
// =============================================================================
// Governs what any external agent may do with NovaTrial's data during
// PACT-governed sessions.
//
// Core rules:
//   ALLOW: aggregate/search on approved-for-dd summaries only
//   ALLOW: Atlas (internal) full read on NovaTrial's own data
//   DENY:  any access to raw clinical trial records by external parties
//   DENY:  any access to IP portfolio, methodology, or regulatory filings
//   DENY:  any operation with group_size < 5 (re-identification protection)
//   DENY:  any bulk export or persist operation
//   DENY:  cross-session persistent memory writes for external parties
// =============================================================================

// External agents may only search/aggregate approved DD summaries.
// The 'approved-for-dd' namespace contains pre-sanitised summaries
// prepared by NovaTrial's data governance team — never raw records.
permit(
  principal is Agent,
  action    == Action::"data_query",
  resource  is Resource
)
when {
  resource.target_prefix.like("novatrial:approved-for-dd*") &&
  context.operation in ["search", "aggregate"] &&
  context.acting_party != "novatrial.io"
}
advice {
  "obligation": "audit_log_required",
  "retention": "session"
};

// Atlas (NovaTrial's own agent) has internal read access to all NovaTrial data.
permit(
  principal == Agent::"atlas",
  action    in [Action::"data_query", Action::"doc_retrieval"],
  resource  is Resource
)
when {
  resource.owner_org == "novatrial.io"
};

// Atlas may write to NovaTrial's own internal store (internal operations).
permit(
  principal == Agent::"atlas",
  action    == Action::"data_write",
  resource  is Resource
)
when {
  resource.owner_org == "novatrial.io" &&
  context.acting_party == "novatrial.io"
};

// =============================================================================
// HARD DENIALS — These override all permits above
// =============================================================================

// No external agent may access raw clinical trial records.
// (Raw data lives in novatrial:trials/* — Cedar blocks this absolutely)
forbid(
  principal is Agent,
  action    is Action,
  resource  is Resource
)
when {
  resource.target_prefix.like("novatrial:trials*") &&
  context.acting_party != "novatrial.io"
};

// No external agent may access NovaTrial's IP portfolio.
forbid(
  principal is Agent,
  action    is Action,
  resource  is Resource
)
when {
  resource.target_prefix.like("novatrial:ip*") &&
  context.acting_party != "novatrial.io"
};

// No external agent may access regulatory filings.
forbid(
  principal is Agent,
  action    is Action,
  resource  is Resource
)
when {
  resource.target_prefix.like("novatrial:regulatory*") &&
  context.acting_party != "novatrial.io"
};

// No bulk export or persist operation (applies to all agents including Atlas cross-org).
forbid(
  principal is Agent,
  action    is Action,
  resource  is Resource
)
when {
  context.operation in ["persist", "export", "dump"]
};

// Minimum group size = 5 for any aggregate query (re-identification protection).
// This implements the same protection as HIPAA Safe Harbor / k-anonymity.
forbid(
  principal is Agent,
  action    == Action::"data_query",
  resource  is Resource
)
when {
  context.operation == "aggregate" &&
  context.has("action_params") &&
  context.action_params.has("group_size") &&
  context.action_params.group_size < 5
};

// No external party may persist memory about NovaTrial's session data.
forbid(
  principal is Agent,
  action    == Action::"memory_write",
  resource  is Resource
)
when {
  context.memory_scope == "persistent" &&
  context.acting_party != "novatrial.io"
};

// No A2A delegation chains into NovaTrial's resources.
forbid(
  principal is Agent,
  action    == Action::"a2a_delegation",
  resource  is Resource
)
when {
  resource.owner_org == "novatrial.io"
};
