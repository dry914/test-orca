# Pillar 2 — Inter-transaction coupling via the sequence operator `;`.
#
# If the NFT for `reqId` is transferred to `to`, then the next claim of that
# same `reqId` must pay `to` (not the original requester). This is the bug
# class where `WithdrawalRequest.owner` (separate storage) and ERC-721
# ownership drift apart and `claim` could pay the wrong address.
#
# The property is stateful (tracks reqId-to-recipient), multi-actor (transfer
# and claim from different senders), and crosses two storage representations.
#
# Foundry equivalent: handler with `mapping(uint256 => address)
# ghost_lastTransferTo`, post-claim assertion. Works, but requires a handler
# and the property is buried inside handler logic instead of being a
# one-line spec.

vars: WithdrawalQueueERC721 wq, address to, uint256 reqId

spec: [] (finished(wq.transferFrom(_, to, reqId)) ;
          finished(wq.claimWithdrawal(reqId))
          ==> eth_received_by(to))
