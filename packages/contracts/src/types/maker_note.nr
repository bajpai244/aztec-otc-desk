use aztec::{
    context::PrivateContext,
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize, ToField},
};
use poseidon::poseidon2::Poseidon2;

#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct MakerNote {
    owner: AztecAddress,
    secret: Field,
}

impl MakerNote {
    pub fn new(owner: AztecAddress) -> Self {
        MakerNote { owner, secret: unsafe { random() } }
    }
    

    pub fn commitment(self) -> Field {
        let preimage = [self.owner.to_field(), self.secret];
        Poseidon2::hash(preimage, 2)
    }

    pub fn commitment_from_context(self, context: &mut PrivateContext) -> Field {
        let preimage = [context.msg_sender().to_field(), self.secret];
        Poseidon2::hash(preimage, 2)
    }
}
