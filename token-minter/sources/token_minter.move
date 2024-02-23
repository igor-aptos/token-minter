module minter::token_minter {
    use aptos_framework::object::{Self, ConstructorRef, Object};
    use aptos_token_objects::collection::{Self, Collection};
    use aptos_token_objects::property_map;
    use aptos_token_objects::royalty;
    use aptos_token_objects::token::{Self, Token};
    use minter::apt_payment;
    use minter::collection_helper;
    use minter::collection_properties;
    use minter::collection_refs;
    use minter::token_helper;
    use minter::whitelist;
    use std::error;
    use std::option::{Self, Option};
    use std::signer;
    use std::string::String;
    use std::vector;

    /// Current version of the token minter
    const VERSION: u64 = 1;

    /// Not the owner of the object
    const ENOT_OBJECT_OWNER: u64 = 1;
    /// The token minter does not exist
    const ETOKEN_MINTER_DOES_NOT_EXIST: u64 = 2;
    /// The collection does not exist
    const ECOLLECTION_DOES_NOT_EXIST: u64 = 3;
    /// The token minter is paused
    const ETOKEN_MINTER_IS_PAUSED: u64 = 4;
    /// The token does not exist
    const ETOKEN_DOES_NOT_EXIST: u64 = 5;
    /// The provided signer is not the creator
    const ENOT_CREATOR: u64 = 6;
    /// The field being changed is not mutable
    const EFIELD_NOT_MUTABLE: u64 = 7;
    /// The token being burned is not burnable
    const ETOKEN_NOT_BURNABLE: u64 = 8;
    /// The property map being mutated is not mutable
    const EPROPERTIES_NOT_MUTABLE: u64 = 9;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenMinter has key {
        /// Version of the token minter
        version: u64,
        /// The collection that the token minter will mint from.
        collection: Object<Collection>,
        /// The address of the creator of the token minter.
        creator: address,
        /// Whether the token minter is paused.
        paused: bool,
        /// The number of tokens minted from the token minter.
        tokens_minted: u64,
        /// Whether only the creator can mint tokens.
        creator_mint_only: bool,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenMinterRefs has key {
        /// Used to generate signer, needed for adding additional guards and minting tokens.
        extend_ref: object::ExtendRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenRefs has key {
        /// Used to generate signer, needed for extending object if needed in the future.
        extend_ref: Option<object::ExtendRef>,
        /// Used to burn.
        burn_ref: Option<token::BurnRef>,
        /// Used to control freeze.
        transfer_ref: Option<object::TransferRef>,
        /// Used to mutate fields
        mutator_ref: Option<token::MutatorRef>,
        /// Used to mutate properties
        property_mutator_ref: property_map::MutatorRef,
    }

    public entry fun init_token_minter(
        creator: &signer,
        description: String,
        max_supply: Option<u64>, // If value is present, collection configured to have a fixed supply.
        name: String,
        uri: String,
        mutable_description: bool,
        mutable_royalty: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        tokens_burnable_by_creator: bool,
        tokens_freezable_by_creator: bool,
        royalty_numerator: u64,
        royalty_denominator: u64,
        creator_mint_only: bool,
        soulbound: bool,
    ) {
        create_token_minter(
            creator, description, max_supply, name, uri, mutable_description, mutable_royalty, mutable_uri,
            mutable_token_description, mutable_token_name, mutable_token_properties, mutable_token_uri,
            tokens_burnable_by_creator, tokens_freezable_by_creator, royalty_numerator, royalty_denominator,
            creator_mint_only, soulbound,
        );
    }

    /// Creates a new collection and token minter, these will each be contained in separate objects.
    /// The collection object will contain the `Collection`, `CollectionRefs`, CollectionProperties`.
    /// The token minter object will contain the `TokenMinter` and `TokenMinterProperties`.
    public fun create_token_minter(
        creator: &signer,
        description: String,
        max_supply: Option<u64>, // If value is present, collection configured to have a fixed supply.
        name: String,
        uri: String,
        mutable_description: bool,
        mutable_royalty: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        tokens_burnable_by_creator: bool,
        tokens_freezable_by_creator: bool,
        royalty_numerator: u64,
        royalty_denominator: u64,
        creator_mint_only: bool,
        soulbound: bool,
    ): Object<TokenMinter> {
        let creator_address = signer::address_of(creator);
        let (constructor_ref, object_signer) = create_object(creator_address);
        let collection_constructor_ref = &collection_helper::create_collection(
            &object_signer,
            description,
            max_supply,
            name,
            option::some(royalty::create(royalty_numerator, royalty_denominator, creator_address)),
            uri,
        );

        let (collection_signer, _) = collection_refs::create_refs(
            collection_constructor_ref,
            mutable_description,
            mutable_uri,
            mutable_royalty,
        );

        collection_properties::create_properties(
            &collection_signer,
            mutable_description,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            tokens_burnable_by_creator,
            tokens_freezable_by_creator,
            soulbound,
        );

        create_token_minter_object(
            &object_signer,
            &constructor_ref,
            object::object_from_constructor_ref(collection_constructor_ref),
            creator_address,
            creator_mint_only,
        )
    }

    public entry fun mint(
        minter: &signer,
        token_minter_object: Object<TokenMinter>,
        name: String,
        description: String,
        uri: String,
        amount: u64,
        property_keys: vector<vector<String>>,
        property_types: vector<vector<String>>,
        property_values: vector<vector<vector<u8>>>,
    ) acquires TokenMinter, TokenMinterRefs {
        mint_token_objects(
            minter, token_minter_object, name, description, uri, amount, property_keys, property_types, property_values,
        );
    }

    /// Anyone can mint if they meet all guard conditions.
    public fun mint_token_objects(
        minter: &signer,
        token_minter_object: Object<TokenMinter>,
        name: String,
        description: String,
        uri: String,
        amount: u64,
        property_keys: vector<vector<String>>,
        property_types: vector<vector<String>>,
        property_values: vector<vector<vector<u8>>>,
    ): vector<Object<Token>> acquires TokenMinter, TokenMinterRefs {
        token_helper::validate_token_properties(amount, &property_keys, &property_types, &property_values);

        let token_minter = borrow_mut(token_minter_object);
        assert!(!token_minter.paused, error::invalid_state(ETOKEN_MINTER_IS_PAUSED));

        let minter_address = signer::address_of(minter);
        if (token_minter.creator_mint_only) {
            assert_token_minter_creator(minter_address, token_minter);
        };

        // Must check ALL guards first before minting
        check_and_execute_guards(minter, token_minter_object, amount);
        token_minter.tokens_minted = token_minter.tokens_minted + amount;

        let tokens = vector[];
        let i = 0;
        let token_minter_signer = &token_minter_signer(token_minter_object);
        while (i < amount) {
            let token = mint_internal(
                minter_address,
                token_minter_signer,
                token_minter.collection,
                description,
                name,
                uri,
                *vector::borrow(&property_keys, i),
                *vector::borrow(&property_types, i),
                *vector::borrow(&property_values, i),
            );
            vector::push_back(&mut tokens, token);
            i = i + 1;
        };

        tokens
    }

    /// This function checks all guards the `token_minter` has and executes them if they are enabled.
    /// This function reverts if any of the guards fail.
    fun check_and_execute_guards(minter: &signer, token_minter: Object<TokenMinter>, amount: u64) {
        let minter_address = signer::address_of(minter);

        if (whitelist::is_whitelist_enabled(token_minter)) {
            whitelist::execute(token_minter, amount, minter_address);
        };
        if (apt_payment::is_apt_payment_enabled(token_minter)) {
            apt_payment::execute(minter, token_minter, amount);
        };
    }

    fun create_token_minter_object(
        object_signer: &signer,
        constructor_ref: &ConstructorRef,
        collection: Object<Collection>,
        creator: address,
        creator_mint_only: bool,
    ): Object<TokenMinter> {
        move_to(object_signer, TokenMinter {
            version: VERSION,
            collection,
            creator,
            paused: false,
            tokens_minted: 0,
            creator_mint_only,
        });
        move_to(object_signer, TokenMinterRefs { extend_ref: object::generate_extend_ref(constructor_ref) });

        object::object_from_constructor_ref(constructor_ref)
    }

    fun mint_internal(
        minter: address,
        token_minter_signer: &signer,
        collection: Object<Collection>,
        description: String,
        name: String,
        uri: String,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
    ): Object<Token> {
        let token_constructor_ref = &token::create(
            token_minter_signer,
            collection::name(collection),
            description,
            name,
            royalty::get(collection),
            uri
        );

        let properties = property_map::prepare_input(property_keys, property_types, property_values);
        property_map::init(token_constructor_ref, properties);

        create_token_refs_and_transfer(
            minter,
            token_minter_signer,
            collection,
            token_constructor_ref,
        )
    }

    fun create_token_refs_and_transfer<T: key>(
        minter: address,
        token_minter_signer: &signer,
        collection: Object<T>,
        token_constructor_ref: &ConstructorRef,
    ): Object<Token> {
        let mutator_ref = if (
            collection_properties::mutable_description(collection)
                || collection_properties::mutable_token_name(collection)
                || collection_properties::mutable_token_uri(collection)) {
            option::some(token::generate_mutator_ref(token_constructor_ref))
        } else {
            option::none()
        };

        let burn_ref = if (collection_properties::tokens_burnable_by_creator(collection)) {
            option::some(token::generate_burn_ref(token_constructor_ref))
        } else {
            option::none()
        };

        move_to(&object::generate_signer(token_constructor_ref), TokenRefs {
            extend_ref: option::some(object::generate_extend_ref(token_constructor_ref)),
            burn_ref,
            transfer_ref: option::none(),
            mutator_ref,
            property_mutator_ref: property_map::generate_mutator_ref(token_constructor_ref),
        });

        token_helper::transfer_token(
            token_minter_signer,
            minter,
            collection_properties::soulbound(collection),
            token_constructor_ref,
        )
    }

    // ================================= Guards ================================= //

    public entry fun add_or_update_whitelist(
        creator: &signer,
        token_minter: Object<TokenMinter>,
        whitelisted_addresses: vector<address>,
        max_mint_per_whitelists: vector<u64>,
    ) acquires TokenMinter, TokenMinterRefs {
        assert_token_minter_creator(signer::address_of(creator), borrow(token_minter));

        whitelist::add_or_update_whitelist(
            &token_minter_signer(token_minter),
            token_minter,
            whitelisted_addresses,
            max_mint_per_whitelists
        );
    }

    public entry fun remove_whitelist_guard(creator: &signer, token_minter: Object<TokenMinter>) acquires TokenMinter {
        assert_token_minter_creator(signer::address_of(creator), borrow(token_minter));
        whitelist::remove_whitelist(token_minter);
    }

    public entry fun add_or_update_apt_payment_guard(
        creator: &signer,
        token_minter: Object<TokenMinter>,
        amount: u64,
        destination: address,
    ) acquires TokenMinter, TokenMinterRefs {
        assert_token_minter_creator(signer::address_of(creator), borrow(token_minter));
        apt_payment::add_or_update_apt_payment(&token_minter_signer(token_minter), token_minter, amount, destination);
    }

    public entry fun remove_apt_payment_guard(
        creator: &signer,
        token_minter: Object<TokenMinter>
    ) acquires TokenMinter {
        assert_token_minter_creator(signer::address_of(creator), borrow(token_minter));
        apt_payment::remove_apt_payment(token_minter);
    }

    // ================================= TokenMinter Mutators ================================= //

    public entry fun set_version(
        creator: &signer,
        token_minter: Object<TokenMinter>,
        version: u64,
    ) acquires TokenMinter {
        let token_minter = borrow_mut(token_minter);
        assert_token_minter_creator(signer::address_of(creator), token_minter);
        token_minter.version = version;
    }

    public entry fun set_paused(
        creator: &signer,
        token_minter: Object<TokenMinter>,
        paused: bool,
    ) acquires TokenMinter {
        let token_minter = borrow_mut(token_minter);
        assert_token_minter_creator(signer::address_of(creator), token_minter);
        token_minter.paused = paused;
    }

    public entry fun set_creator_mint_only(
        creator: &signer,
        token_minter: Object<TokenMinter>,
        creator_mint_only: bool,
    ) acquires TokenMinter {
        let token_minter = borrow_mut(token_minter);
        assert_token_minter_creator(signer::address_of(creator), token_minter);
        token_minter.creator_mint_only = creator_mint_only;
    }

    /// Destroys the token minter, this is done after the collection has been fully minted.
    /// Assert that only the creator can call this function.
    /// Assert that the creator owns the collection.
    public entry fun destroy_token_minter(
        creator: &signer,
        token_minter_object: Object<TokenMinter>,
    ) acquires TokenMinter {
        let creator_address = signer::address_of(creator);
        let token_minter = borrow(token_minter_object);

        assert_token_minter_creator(creator_address, token_minter);
        assert!(object::owns(token_minter_object, creator_address), error::permission_denied(ENOT_OBJECT_OWNER));

        let TokenMinter {
            version: _,
            collection: _,
            creator: _,
            paused: _,
            tokens_minted: _,
            creator_mint_only: _,
        } = move_from<TokenMinter>(object::object_address(&token_minter_object));
    }

    // ================================= Collection Mutators ================================= //

    public entry fun set_collection_royalties<T: key>(
        creator: &signer,
        collection: Object<T>,
        royalty_numerator: u64,
        royalty_denominator: u64,
        payee_address: address,
    ) {
        let royalty = royalty::create(royalty_numerator, royalty_denominator, payee_address);
        collection_refs::set_collection_royalties(creator, collection, royalty);
    }

    // ================================= Token Mutators ================================= //

    public entry fun set_token_description<T: key>(
        creator: &signer,
        token: Object<Token>,
        description: String,
    ) acquires TokenRefs {
        assert!(
            collection_properties::mutable_token_description(token::collection_object(token)),
            error::permission_denied(EFIELD_NOT_MUTABLE),
        );
        token::set_description(option::borrow(&authorized_borrow_token_refs(token, creator).mutator_ref), description);
    }

    // ================================= View Functions ================================= //

    fun token_minter_signer(token_minter: Object<TokenMinter>): signer acquires TokenMinterRefs {
        let extend_ref = &borrow_refs(&token_minter).extend_ref;
        object::generate_signer_for_extending(extend_ref)
    }

    fun create_object(creator_address: address): (ConstructorRef, signer) {
        let constructor_ref = object::create_object(creator_address);
        let object_signer = object::generate_signer(&constructor_ref);
        (constructor_ref, object_signer)
    }

    fun token_address<T: key>(token: &Object<T>): address {
        let token_address = object::object_address(token);
        assert!(exists<TokenRefs>(token_address), error::not_found(ETOKEN_DOES_NOT_EXIST));
        token_address
    }

    fun token_minter_address<T: key>(token_minter: &Object<T>): address {
        let token_minter_address = object::object_address(token_minter);
        assert!(exists<TokenMinter>(token_minter_address), error::not_found(ETOKEN_MINTER_DOES_NOT_EXIST));
        token_minter_address
    }

    fun assert_token_minter_creator(creator: address, token_minter: &TokenMinter) {
        assert!(token_minter.creator == creator, error::invalid_argument(ENOT_CREATOR));
    }

    fun assert_owner<T: key>(owner: address, object: Object<T>) {
        assert!(object::owner(object) == owner, error::invalid_argument(ENOT_OBJECT_OWNER));
    }

    inline fun borrow<T: key>(token_minter: Object<T>): &TokenMinter acquires TokenMinter {
        borrow_global<TokenMinter>(token_minter_address(&token_minter))
    }

    inline fun borrow_mut<T: key>(token_minter: Object<T>): &mut TokenMinter acquires TokenMinter {
        borrow_global_mut<TokenMinter>(token_minter_address(&token_minter))
    }

    inline fun borrow_refs(token_minter: &Object<TokenMinter>): &TokenMinterRefs acquires TokenMinterRefs {
        borrow_global<TokenMinterRefs>(token_minter_address(token_minter))
    }

    inline fun authorized_borrow_token_refs(token: Object<Token>, creator: &signer): &TokenRefs {
        let token_refs = borrow_global<TokenRefs>(token_address(&token));
        assert_owner(signer::address_of(creator), token);
        token_refs
    }

    #[view]
    public fun version(token_minter: Object<TokenMinter>): u64 acquires TokenMinter {
        borrow(token_minter).version
    }

    #[view]
    public fun collection(token_minter: Object<TokenMinter>): Object<Collection> acquires TokenMinter {
        borrow(token_minter).collection
    }

    #[view]
    public fun creator(token_minter: Object<TokenMinter>): address acquires TokenMinter {
        borrow(token_minter).creator
    }

    #[view]
    public fun paused(token_minter: Object<TokenMinter>): bool acquires TokenMinter {
        borrow(token_minter).paused
    }

    #[view]
    public fun tokens_minted(token_minter: Object<TokenMinter>): u64 acquires TokenMinter {
        borrow(token_minter).tokens_minted
    }

    #[view]
    public fun creator_mint_only(token_minter: Object<TokenMinter>): bool acquires TokenMinter {
        borrow(token_minter).creator_mint_only
    }
}