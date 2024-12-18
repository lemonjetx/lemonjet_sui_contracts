module lemonjet_sui::house_data {
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::package::{Self};

        // Error codes
    const ECallerNotHouse: u64 = 0;
    const EInsufficientBalance: u64 = 1;


    public struct HouseData has key {
        id: UID,
        balance: Balance<SUI>, // House's balance which also contains the acrued winnings of the house.
        house: address,
    }

    public struct HouseCap has key {
        id: UID
    }

    public struct HOUSE_DATA has drop {}

    fun init(otw: HOUSE_DATA , ctx: &mut TxContext) {
        package::claim_and_keep(otw, ctx);

        let house_cap = HouseCap {
            id: object::new(ctx)
        };

        transfer::transfer(house_cap, ctx.sender());
    }

      public fun initialize_house_data(house_cap: HouseCap, coin: Coin<SUI>, ctx: &mut TxContext) {
        assert!(coin.value() > 0, EInsufficientBalance);

    let house_data = HouseData {
      id: object::new(ctx),
      balance: coin.into_balance(),
      house: ctx.sender(),
    };

    let HouseCap { id } = house_cap;
    object::delete(id);

    transfer::share_object(house_data);
  }

    public fun top_up(house_data: &mut HouseData, coin: Coin<SUI>, _: &mut TxContext) {
        coin::put(&mut house_data.balance, coin)
    }

       public fun withdraw(house_data: &mut HouseData, ctx: &mut TxContext) {
        assert!(ctx.sender() == house_data.house, ECallerNotHouse);

        let total_balance = balance(house_data);
        let coin = coin::take(&mut house_data.balance, total_balance, ctx);
        transfer::public_transfer(coin, house_data.house());
    }



      /// Returns a mutable reference to the balance of the house.
    public(package) fun borrow_balance_mut(house_data: &mut HouseData): &mut Balance<SUI> {
        &mut house_data.balance
    }


    /// Returns a mutable reference to the house id.
    public(package) fun borrow_mut(house_data: &mut HouseData): &mut UID {
        &mut house_data.id
    }

    // --------------- HouseData Accessors ---------------

    /// Returns a reference to the house id.
    public(package) fun borrow(house_data: &HouseData): &UID {
        &house_data.id
    }

    /// Returns the balance of the house.
    public fun balance(house_data: &HouseData): u64 {
        house_data.balance.value()
    }

    /// Returns the address of the house.
    public fun house(house_data: &HouseData): address {
        house_data.house
    }




    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(HOUSE_DATA {}, ctx);
    }

}