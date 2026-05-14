# Pillar 3 — State implication without enumeration (free variable form).
#
# Original PDF intent:
#   if any finalized-but-unclaimed request exists, locked ether must be positive.
#
# Encoding caveat — first iteration:
#   The "is this request claimed?" predicate sits in WithdrawalQueueBase's
#   private `queue` storage; only the public `getWithdrawalStatus(uint256[])`
#   getter exposes the `isClaimed` flag (index 5 of WithdrawalRequestStatus),
#   and it takes an array argument. Once we either (a) wire a `WQView.isClaimed`
#   helper view or (b) confirm [V] supports array-literal arguments to view
#   calls + double indexing, the precondition should become
#       !wq.getWithdrawalStatus([reqId])[0][5]
#   (or `!wqView.isClaimed(reqId)`).
#
# For now we keep the free-variable witness search but drop the `!claimed`
# leg — the spec is weaker (it triggers on ANY finalized id, not just
# unclaimed ones), but it preserves the pillar-3 mechanic and parses cleanly.
#
# Derived from: contracts/0.8.9/WithdrawalQueueBase.sol — getLastFinalizedRequestId,
# getLockedEtherAmount.

vars: WithdrawalQueueERC721 wq, uint256 reqId

inv: (reqId > 0 && reqId <= wq.getLastFinalizedRequestId())
     ==> wq.getLockedEtherAmount() > 0
