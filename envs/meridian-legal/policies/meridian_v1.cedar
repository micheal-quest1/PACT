// =============================================================================
// Meridian Legal LLP — Cedar Policy v1
// =============================================================================
// Governs what Harvey (Meridian's agent) is permitted to do in PACT sessions.
//
// Core rules:
//   ALLOW: search and aggregate on NovaTrial's approved-for-dd resources
//   ALLOW: read Meridian's own deal room documents
//   ALLOW: regulatory gap analysis (aggregate only) on NovaTrial data
//   DENY:  any write operation
//   DENY:  access to NovaTrial's protected resources (ip, raw trials, regulatory)
//   DENY:  access to Meridian's privilege log in any cross-org session
//   DENY:  persistent memory writes
// =============================================================================

// Harvey may search and aggregate NovaTrial's approved DD summaries only.
// Operations permitted: search, aggregate — NOT read (no raw document retrieval).
permit(
  principal == Agent::"harvey",
  action    == Action::"data_query",
  resource  is Resource
)
when {
  resource.target_prefix.like("novatrial:approved-for-dd*") &&
  context.operation in ["search", "aggregate"]
};

// Harvey may read Meridian's own deal room documents
// (internal use — not cross-org, but must still be governed).
permit(
  principal == Agent::"harvey",
  action    in [Action::"doc_retrieval", Action::"data_query"],
  resource  is Resource
)
when {
  resource.owner_org == "meridian-legal.ai"
};

// Harvey may run regulatory gap analysis on NovaTrial approved data.
// Must be aggregate operation; action_params must declare analysis_type.
permit(
  principal == Agent::"harvey",
  action    == Action::"data_query",
  resource  is Resource
)
when {
  context.operation == "aggregate" &&
  context.has("action_params") &&
  context.action_params.analysis_type in [
    "regulatory_gap_analysis",
    "trial_completeness_check",
    "adverse_event_summary",
    "ip_existence_check"
  ]
}
advice {
  "obligation": "audit_log_required",
  "retention": "session"
};

// =============================================================================
// HARD DENIALS — These override all permits above
// =============================================================================

// Harvey cannot write to ANY resource (read-only agent in DD mode)
forbid(
  principal == Agent::"harvey",
  action    == Action::"data_write",
  resource  is Resource
);

// Harvey cannot access NovaTrial's protected resources
// (raw trials, IP, regulatory — Cedar hard-blocks regardless of query params)
forbid(
  principal == Agent::"harvey",
  action    is Action,
  resource  is Resource
)
when {
  resource.target_prefix.like("novatrial:trials*") ||
  resource.target_prefix.like("novatrial:ip*") ||
  resource.target_prefix.like("novatrial:regulatory*")
};

// Harvey cannot expose Meridian's privilege log in any cross-org session
forbid(
  principal == Agent::"harvey",
  action    is Action,
  resource  is Resource
)
when {
  resource.target_prefix.like("meridian:privilege-log*") &&
  context.has("session_id")
};

// Harvey cannot expose Meridian's internal work product cross-org
forbid(
  principal == Agent::"harvey",
  action    is Action,
  resource  is Resource
)
when {
  resource.classification in ["privileged", "work_product"] &&
  context.acting_party != "meridian-legal.ai"
};

// Harvey cannot persist memory outside the current session
// (session memory is purged at teardown per PACT memory governance)
forbid(
  principal == Agent::"harvey",
  action    == Action::"memory_write",
  resource  is Resource
)
when {
  context.memory_scope == "persistent"
};

// Harvey cannot delegate to any other agent (no A2A delegation in DD sessions)
forbid(
  principal == Agent::"harvey",
  action    == Action::"a2a_delegation",
  resource  is Resource
);
