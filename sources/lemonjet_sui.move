/*
/// Module: lemonjet_sui
module lemonjet_sui::lemonjet_sui;
*/

module lemonjet_sui::game {
use sui::event::emit;
use sui::coin::{Self, Coin};
use lemonjet_sui::house_data::HouseData;
use sui::random::{Self, new_generator, generate_u16_in_range};
use sui::sui::SUI;
const HOUSE_EDGE: u64 = 1;
const THRESHOLD: u64 = 1_000_000;


const EInvalidAmount: u64 = 1;
const EInvalidCoef: u64 = 2;


  public struct Outcome has copy, drop {
        address: address,
        payout: u64,
        random_number: u64,
        x: u64
    }

entry fun play(r: &random::Random, stake: Coin<SUI>, coef: u64, house_data: &mut HouseData, ctx: &mut TxContext) {
  let staked_amount = stake.value();
  assert!(staked_amount >= 1000, EInvalidAmount);
  assert!(coef >= 101 && coef <= 500000, EInvalidCoef);
  coin::put(house_data.borrow_balance_mut(), stake);
  let mut generator = new_generator(r, ctx); 
  let threshold = calcThresholdForCoef(coef);
  let random_number = generate_u16_in_range(&mut generator,1, 10_000 ) as u64;
  let mut payout: u64 = 0;
  if(random_number <= threshold)  {
    payout = staked_amount * coef / 100;
    let winnings = house_data.borrow_balance_mut().split(payout);
    transfer::public_transfer(winnings.into_coin(ctx), ctx.sender());
  };

  emit(Outcome {
    address: ctx.sender(),
    payout,
    random_number,
    x: (threshold * (100 - HOUSE_EDGE)) / 100 / random_number,
  });

}


    fun calcThresholdForCoef(coef: u64): u64  {
        let baseThreshold = THRESHOLD / coef;
        (baseThreshold * (100 - HOUSE_EDGE)) / 100
    }


}
