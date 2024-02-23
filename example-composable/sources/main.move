module example_composable::main {
    #[test_only]
    use aptos_framework::object;
    #[test_only]
    use minter::token_minter::{create_token_minter, mint_token_objects};
    #[test_only]
    use std::option;
    #[test_only]
    use std::signer::{address_of};
    #[test_only]
    use std::string::{utf8};
    #[test_only]
    use std::vector;

    #[test(creator = @0x123, user = @0x456)]
    fun main(creator: &signer, user: &signer) {
        let user_addr = address_of(user);

        let sword_token_minter_obj = create_token_minter(
            creator,
            utf8(b"sword collection"),
            option::none(),
            utf8(b"swords"),
            utf8(b"https://example.com/swords"),
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            0,
            100,
            true, // creator_mint_only
            false,
        );
        let powerup_token_minter_obj = create_token_minter(
            creator,
            utf8(b"powerup collection"),
            option::none(),
            utf8(b"powerups"),
            utf8(b"https://example.com/powerups"),
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            0,
            100,
            true, // creator_mint_only
            false,
        );

        let sword_token_objs = mint_token_objects(
            creator,
            sword_token_minter_obj,
            utf8(b"Sword"),
            utf8(b"A fancy sword"),
            utf8(b"https://example.com/sword1.png"),
            1,
            vector[vector[]],
            vector[vector[]],
            vector[vector[]],
        );
        let powerup_token_objs = mint_token_objects(
            creator,
            powerup_token_minter_obj,
            utf8(b"Powerup"),
            utf8(b"A fancy powerup"),
            utf8(b"https://example.com/powerup1.png"),
            1,
            vector[vector[]],
            vector[vector[]],
            vector[vector[]],
        );
        let sword_token_obj = *vector::borrow(&sword_token_objs, 0);
        let powerup_token_obj = *vector::borrow(&powerup_token_objs, 0);
        let sword_token_addr = object::object_address(&sword_token_obj);
        object::transfer(creator, sword_token_obj, user_addr);
        object::transfer(creator, powerup_token_obj, sword_token_addr);

        assert!(object::owner(sword_token_obj) == user_addr, 0);
        assert!(object::owner(powerup_token_obj) == sword_token_addr, 1);

        // TODO: Test sword token owner transferring out the powerup token
        // TODO: Test collection owner transferring out the powerup token
    }
}