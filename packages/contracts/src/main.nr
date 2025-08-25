use aztec::macros::aztec;
pub mod types;

#[aztec]
pub contract OTCEscrowContract {
    // aztec library imports
    use aztec::{
        macros::{
            functions::{initializer, private, utility},
            storage::storage
        },
        prelude::{AztecAddress, PrivateImmutable, PrivateMutable},
        messages::logs::note::encode_and_encrypt_note,
        protocol_types::traits::ToField,

    };
    use crate::types::{
        definition_note::DefinitionNote,
        maker_note::MakerNote
    };

    use poseidon::poseidon2::Poseidon2;
    use token_contract::Token;
    

    #[storage]
    struct Storage<Context> {
        definition: PrivateImmutable<DefinitionNote, Context>,
        maker_secret: PrivateImmutable<MakerNote, Context>,
    }
    
    #[private]
    #[initializer]
    fn constructor(
        offer_token_address: AztecAddress,
        offer_token_amount: u128,
        ask_token_address: AztecAddress,
        ask_token_amount: u128,
    ) {
        // Create a maker secret note
        let caller = context.msg_sender();
        let maker_note = MakerNote::new(caller);
        storage.maker_secret.initialize(maker_note).emit(encode_and_encrypt_note(
            &mut context,
            context.msg_sender(),
            context.msg_sender()
        ));
       
        // Create definition note
        let self_address = context.this_address();
        let definition = DefinitionNote::new(
            self_address,
            maker_note.commitment(),
            offer_token_address,
            offer_token_amount,
            ask_token_address,
            ask_token_amount
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
     * @param maker_secret - the secret value used to bind the market maker
     *                       retrieve with `get_maker_secret` to avoid extra work
     * @param _nonce - authwit nonce used in `transfer_private_to_private`
     */
    #[private]
    fn deposit_tokens(maker_secret: Field, _nonce: Field) {

        let self_address = context.this_address();
        let caller = context.msg_sender();

        // check maker commitment
        let definition = storage.definition.get_note();
        let commitment = compute_maker_commitment(caller, maker_secret);
        definition.check_commitment(commitment);

        // transfer tokens in
        Token::at(definition.offer_token_address)
            .transfer_private_to_private(
                caller,
                self_address,
                definition.offer_token_amount,
                _nonce,
            )
            .call(&mut context);
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
        Token::at(definition.ask_token_address)
            .transfer_private_to_private(
                caller,
                self_address,
                definition.ask_token_amount,
                _nonce
            )
            .call(&mut context);

        // transfer offer tokens out
        Token::at(definition.offer_token_address)
            .transfer_private_to_private(
                self_address,
                caller,
                definition.offer_token_amount,
                0
            )
            .call(&mut context);
    }

    /**
     * Finalize the OTC order by claiming the offered tokens as the maker
     *
     * @param maker_secret - the secret value used to bind the market maker
     */
    #[private]
    fn finalize_order(maker_secret: Field) {
        let self_address = context.this_address();
        let caller = context.msg_sender();

        // check maker commitment
        let definition = storage.definition.get_note();
        let commitment = compute_maker_commitment(caller, maker_secret);
        definition.check_commitment(commitment);

        // transfer asked tokens out
        Token::at(definition.ask_token_address)
            .transfer_private_to_private(
                self_address,
                caller,
                definition.ask_token_amount,
                0
            )
            .call(&mut context);
    }

    #[utility]
    pub unconstrained fn get_definition() -> DefinitionNote {
        storage.definition.view_note()
    }

    #[utility]
    pub unconstrained fn get_maker_secret() -> Field {
        storage.maker_secret.view_note().secret
    }

    #[contract_library_method]
    pub fn compute_maker_commitment(maker_address: AztecAddress, maker_secret: Field) -> Field {
        let preimage = [maker_address.to_field(), maker_secret];
        Poseidon2::hash(preimage, 2)
    }
}
