use std::fmt::Debug;

use async_trait::async_trait;
use eyre::Result;
use hyperlane_base::db::HyperlaneRocksDB;
use hyperlane_core::{
    GasPaymentKey, HyperlaneMessage, InterchainGasExpenditure, InterchainGasPayment,
    TxCostEstimate, TxOutcome, U256,
};
use tracing::{debug, error, trace};

use self::policies::{GasPaymentPolicyMinimum, GasPaymentPolicyNone};
use crate::{
    msg::gas_payment::policies::GasPaymentPolicyOnChainFeeQuoting,
    settings::{
        matching_list::MatchingList, GasPaymentEnforcementConf, GasPaymentEnforcementPolicy,
    },
};

mod policies;

#[async_trait]
pub trait GasPaymentPolicy: Debug + Send + Sync {
    /// Returns Some(gas_limit) if the policy has approved the transaction or
    /// None if the transaction is not approved.
    async fn message_meets_gas_payment_requirement(
        &self,
        message: &HyperlaneMessage,
        current_payment: &InterchainGasPayment,
        current_expenditure: &InterchainGasExpenditure,
        tx_cost_estimate: &TxCostEstimate,
    ) -> Result<Option<U256>>;
}

#[derive(Debug)]
pub struct GasPaymentEnforcer {
    /// List of policies and a whitelist to decide if it should be used for a
    /// given transaction. It is highly recommended to have the last policy
    /// use a wild-card white list to ensure all messages fall into one
    /// policy or another. If a message matches multiple policies'
    /// whitelists, then whichever is first in the list will be used.
    policies: Vec<(Box<dyn GasPaymentPolicy>, MatchingList)>,
    db: HyperlaneRocksDB,
}

impl GasPaymentEnforcer {
    pub fn new(
        policy_configs: impl IntoIterator<Item = GasPaymentEnforcementConf>,
        db: HyperlaneRocksDB,
    ) -> Self {
        let policies = policy_configs
            .into_iter()
            .map(|cfg| {
                let p: Box<dyn GasPaymentPolicy> = match cfg.policy {
                    GasPaymentEnforcementPolicy::None => Box::new(GasPaymentPolicyNone),
                    GasPaymentEnforcementPolicy::Minimum { payment } => {
                        Box::new(GasPaymentPolicyMinimum::new(payment))
                    }
                    GasPaymentEnforcementPolicy::OnChainFeeQuoting {
                        gas_fraction_numerator: n,
                        gas_fraction_denominator: d,
                    } => Box::new(GasPaymentPolicyOnChainFeeQuoting::new(n, d)),
                };
                (p, cfg.matching_list)
            })
            .collect();

        Self { policies, db }
    }
}

impl GasPaymentEnforcer {
    /// Returns Some(gas_limit) if the enforcer has approved the transaction or
    /// None if the transaction is not approved.
    pub async fn message_meets_gas_payment_requirement(
        &self,
        message: &HyperlaneMessage,
        tx_cost_estimate: &TxCostEstimate,
    ) -> Result<Option<U256>> {
        let msg_id = message.id();
        let gas_payment_key = GasPaymentKey {
            message_id: msg_id,
            destination: message.destination,
        };
        let current_payment = self
            .db
            .retrieve_gas_payment_by_gas_payment_key(gas_payment_key)?;
        let current_expenditure = self.db.retrieve_gas_expenditure_by_message_id(msg_id)?;
        for (policy, whitelist) in &self.policies {
            if !whitelist.msg_matches(message, true) {
                trace!(
                    msg=%message,
                    ?policy,
                    ?whitelist,
                    "Message did not match whitelist for policy"
                );
                continue;
            }

            trace!(
                msg=%message,
                ?policy,
                ?whitelist,
                "Message matched whitelist for policy"
            );
            debug!(
                msg=%message,
                ?policy,
                ?current_payment,
                ?current_expenditure,
                "Evaluating if message meets gas payment requirement",
            );
            return policy
                .message_meets_gas_payment_requirement(
                    message,
                    &current_payment,
                    &current_expenditure,
                    tx_cost_estimate,
                )
                .await;
        }

        error!(
            msg=%message,
            policies=?self.policies,
            "No gas payment policy matched for message; consider adding a default policy to the end of the policies array which uses a wildcard whitelist."
        );
        Ok(None)
    }

    pub fn record_tx_outcome(&self, message: &HyperlaneMessage, outcome: TxOutcome) -> Result<()> {
        self.db.process_gas_expenditure(InterchainGasExpenditure {
            message_id: message.id(),
            gas_used: outcome.gas_used,
            tokens_used: outcome.gas_used * outcome.gas_price,
        })?;
        Ok(())
    }
}

#[cfg(test)]
mod test {
    use std::str::FromStr;

    use hyperlane_base::db::{test_utils, HyperlaneRocksDB};
    use hyperlane_core::{
        HyperlaneDomain, HyperlaneMessage, InterchainGasPayment, LogMeta, TxCostEstimate, H160,
        H256, U256,
    };

    use super::GasPaymentEnforcer;
    use crate::settings::{
        matching_list::MatchingList, GasPaymentEnforcementConf, GasPaymentEnforcementPolicy,
    };

    #[tokio::test]
    async fn test_empty_whitelist() {
        test_utils::run_test_db(|db| async move {
            let hyperlane_db = HyperlaneRocksDB::new(
                &HyperlaneDomain::new_test_domain("test_empty_whitelist"),
                db,
            );

            let enforcer = GasPaymentEnforcer::new(
                // Require a payment
                vec![GasPaymentEnforcementConf {
                    policy: GasPaymentEnforcementPolicy::Minimum {
                        payment: U256::one(),
                    },
                    matching_list: Default::default(),
                }],
                hyperlane_db,
            );

            // Ensure that message without any payment is considered as not meeting the
            // requirement because it doesn't match the GasPaymentEnforcementPolicy
            assert_eq!(
                enforcer
                    .message_meets_gas_payment_requirement(
                        &HyperlaneMessage::default(),
                        &TxCostEstimate::default(),
                    )
                    .await
                    .unwrap(),
                None
            );
        })
        .await;
    }

    #[tokio::test]
    async fn test_no_match() {
        #[allow(unused_must_use)]
        test_utils::run_test_db(|db| async move {
            let hyperlane_db =
                HyperlaneRocksDB::new(&HyperlaneDomain::new_test_domain("test_no_match"), db);
            let matching_list = serde_json::from_str(r#"[{"origindomain": 234}]"#).unwrap();
            let enforcer = GasPaymentEnforcer::new(
                // Require a payment
                vec![GasPaymentEnforcementConf {
                    policy: GasPaymentEnforcementPolicy::None,
                    matching_list,
                }],
                hyperlane_db,
            );

            assert!(matches!(
                enforcer
                    .message_meets_gas_payment_requirement(
                        &HyperlaneMessage::default(),
                        &TxCostEstimate::default(),
                    )
                    .await,
                Ok(None)
            ));
        })
        .await;
    }

    #[tokio::test]
    async fn test_different_destinations() {
        #[allow(unused_must_use)]
        test_utils::run_test_db(|db| async move {
            let msg = HyperlaneMessage {
                destination: 123,
                ..HyperlaneMessage::default()
            };

            let hyperlane_db = HyperlaneRocksDB::new(
                &HyperlaneDomain::new_test_domain("test_different_destinations"),
                db,
            );
            let enforcer = GasPaymentEnforcer::new(
                vec![GasPaymentEnforcementConf {
                    policy: GasPaymentEnforcementPolicy::Minimum {
                        payment: U256::one(),
                    },
                    matching_list: MatchingList::default(),
                }],
                hyperlane_db.clone(),
            );

            let wrong_destination_payment = InterchainGasPayment {
                message_id: msg.id(),
                destination: 456,
                payment: U256::one(),
                gas_amount: U256::one(),
            };
            hyperlane_db.process_gas_payment(wrong_destination_payment, &LogMeta::random());
            // Ensure if the gas payment was made to the incorrect destination, it does not meet
            // the requirement
            assert!(enforcer
                .message_meets_gas_payment_requirement(&msg, &TxCostEstimate::default(),)
                .await
                .unwrap()
                .is_none());

            let correct_destination_payment = InterchainGasPayment {
                message_id: msg.id(),
                destination: msg.destination,
                payment: U256::one(),
                gas_amount: U256::one(),
            };
            hyperlane_db.process_gas_payment(correct_destination_payment, &LogMeta::random());
            // Ensure if the gas payment was made to the correct destination, it meets the
            // requirement
            assert!(enforcer
                .message_meets_gas_payment_requirement(&msg, &TxCostEstimate::default(),)
                .await
                .unwrap()
                .is_some());
        })
        .await;
    }

    #[tokio::test]
    async fn test_half_and_half_payment() {
        #[allow(unused_must_use)]
        test_utils::run_test_db(|db| async move {
            let msg = HyperlaneMessage {
                destination: 123,
                ..HyperlaneMessage::default()
            };

            let hyperlane_db = HyperlaneRocksDB::new(
                &HyperlaneDomain::new_test_domain("test_half_and_half_payment"),
                db,
            );

            let enforcer = GasPaymentEnforcer::new(
                vec![GasPaymentEnforcementConf {
                    policy: GasPaymentEnforcementPolicy::Minimum {
                        payment: U256::from(2),
                    },
                    matching_list: MatchingList::default(),
                }],
                hyperlane_db.clone(),
            );

            let initial_payment = InterchainGasPayment {
                message_id: msg.id(),
                destination: msg.destination,
                payment: U256::one(),
                gas_amount: U256::one(),
            };
            hyperlane_db.process_gas_payment(initial_payment, &LogMeta::random());

            // Ensure if only half gas payment was made, it does not meet the requirement
            assert!(enforcer
                .message_meets_gas_payment_requirement(&msg, &TxCostEstimate::default(),)
                .await
                .unwrap()
                .is_none());

            let deficit_payment = InterchainGasPayment {
                message_id: msg.id(),
                destination: msg.destination,
                payment: U256::one(),
                gas_amount: U256::one(),
            };
            hyperlane_db.process_gas_payment(deficit_payment, &LogMeta::random());
            // Ensure if the full gas payment was made, it meets the requirement
            assert!(enforcer
                .message_meets_gas_payment_requirement(&msg, &TxCostEstimate::default(),)
                .await
                .unwrap()
                .is_some());
        })
        .await;
    }

    #[tokio::test]
    async fn test_non_empty_matching_list() {
        test_utils::run_test_db(|db| async move {
            let hyperlane_db = HyperlaneRocksDB::new(&HyperlaneDomain::new_test_domain("test_non_empty_matching_list"), db);

            let sender_address = "0xaa000000000000000000000000000000000000aa";
            let recipient_address = "0xbb000000000000000000000000000000000000bb";

            let matching_list = serde_json::from_str(
                &format!(r#"[{{"senderaddress": "{sender_address}", "recipientaddress": "{recipient_address}"}}]"#)
            ).unwrap();

            let enforcer = GasPaymentEnforcer::new(
                vec![
                    GasPaymentEnforcementConf {
                        // No payment for special cases
                        policy: GasPaymentEnforcementPolicy::None,
                        matching_list,
                    },
                    GasPaymentEnforcementConf {
                        // All other messages must pass a minimum
                        policy: GasPaymentEnforcementPolicy::Minimum {
                            payment: U256::one(),
                        },
                        matching_list: MatchingList::default(),
                    },
                ],
                hyperlane_db,
            );

            let sender: H256 = H160::from_str(sender_address).unwrap().into();
            let recipient: H256 = H160::from_str(recipient_address).unwrap().into();

            let matching_message = HyperlaneMessage {
                sender,
                recipient,
                ..HyperlaneMessage::default()
            };

            // The message should meet the requirement because it's on the whitelist for the first
            // policy, even though it would not pass the second (default) policy.
            assert!(enforcer
                .message_meets_gas_payment_requirement(
                    &matching_message,
                    &TxCostEstimate::default(),
                )
                .await
                .unwrap()
                .is_some());

            // Switch the sender & recipient
            let not_matching_message = HyperlaneMessage {
                sender: recipient,
                recipient: sender,
                ..HyperlaneMessage::default()
            };

            // The message should not meet the requirement because it's NOT on the first whitelist
            // and doesn't satisfy the GasPaymentEnforcementPolicy
            assert!(enforcer
                .message_meets_gas_payment_requirement(
                    &not_matching_message,
                    &TxCostEstimate::default(),
                )
                .await
                .unwrap()
                .is_none());
        })
        .await;
    }
}
