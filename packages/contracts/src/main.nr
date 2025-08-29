use aztec::macros::aztec;

pub mod types;
pub mod test;

#[aztec]
pub contract OTCEscrowContract {
    // aztec library imports
    use aztec::{
        macros::{
            functions::{initializer, private, utility},
            storage::storage
        },
        oracle::debug_log::{debug_log, debug_log_format},
        prelude::{AztecAddress, PrivateImmutable, PrivateMutable},
        messages::logs::note::encode_and_encrypt_note,
        protocol_types::traits::ToField,
    };
    use crate::types::definition_note::DefinitionNote;

    use token_contract::Token;

    #[storage]
    struct Storage<Context> {
        definition: PrivateImmutable<DefinitionNote, Context>,
    }
    
    #[private]
    #[initializer]
    fn constructor(
        sell_token_address: AztecAddress,
        sell_token_amount: u128,
        buy_token_address: AztecAddress,
        buy_token_amount: u128,
    ) {
        let self_address = context.this_address();
        let caller = context.msg_sender();

        // create partial note
        let partial_note = Token::at(buy_token_address)
            .initialize_transfer_commitment(
                self_address,
                caller,
                self_address
            ).call(&mut context);

        // Create definition note
        let definition = DefinitionNote::new(
            self_address,
            partial_note,
            sell_token_address,
            sell_token_amount,
            buy_token_address,
            buy_token_amount
        );
        
        storage.definition.initialize(definition).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));
    }
    
    /**
     * OTC Offer Maker deposits tokens into the shared escrow
     *
     * @param _nonce - authwit nonce used in `transfer_private_to_private`
     * @return - the commitment for the partial note
     */
    #[private]
    fn deposit_tokens(_nonce: Field) {

        let definition = storage.definition.get_note();
        let self_address = context.this_address();
        let caller = context.msg_sender();

        // transfer tokens in
        Token::at(definition.sell_token_address)
            .transfer_private_to_private(
                caller,
                self_address,
                definition.sell_token_amount,
                _nonce
            )
            .call(&mut context);

        // emit nullifier to prevent multiple deposits
        let deposit_nullifier = definition.get_nullifier();
        context.push_nullifier(deposit_nullifier);
    }

    /**
     * Fulfil an OTC order as a taker by transfering in the asked tokens and withdrawing the offered tokens
     *
     * @param _nonce - authwit nonce used in `transfer_private_to_private`
     */
    #[private]
    fn fill_order(_nonce: Field) {
        let definition = storage.definition.get_note();
        let self_address = context.this_address();
        let caller = context.msg_sender();

        // transfer ask tokens in
        Token::at(definition.buy_token_address)
            .transfer_private_to_private(
                caller,
                self_address,
                definition.buy_token_amount,
                _nonce
            )
            .call(&mut context);

        Token::at(definition.buy_token_address)
            .transfer_private_to_commitment(
                self_address,
                definition.partial_note,
                definition.buy_token_amount,
                0
            )
            .call(&mut context);

        // transfer offer tokens out
        Token::at(definition.sell_token_address)
            .transfer_private_to_private(
                self_address,
                caller,
                definition.sell_token_amount,
                0
            )
            .call(&mut context);
    }

    #[utility]
    pub unconstrained fn get_definition() -> DefinitionNote {
        storage.definition.view_note()
    }
}
