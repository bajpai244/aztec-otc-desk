use aztec::{
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize},
};

#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct DefinitionNote {
    owner: AztecAddress,
    maker_commitment: Field,
    offer_token_address: AztecAddress,
    offer_token_amount: u128,
    ask_token_address: AztecAddress,
    ask_token_amount: u128,
}

impl DefinitionNote {
    pub fn new(
        owner: AztecAddress,
        maker_commitment: Field,
        offer_token_address: AztecAddress,
        offer_token_amount: u128,
        ask_token_address: AztecAddress,
        ask_token_amount: u128,
    ) -> Self {
        DefinitionNote {
            owner,
            maker_commitment,
            offer_token_address,
            offer_token_amount,
            ask_token_address,
            ask_token_amount,
        }
    }

    pub fn check_commitment(self, asserted_commitment: Field) {
        assert(self.maker_commitment == asserted_commitment);
    }
}
