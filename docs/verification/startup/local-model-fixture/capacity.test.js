const assert = require('node:assert/strict');
const { availableSeats } = require('./capacity');
assert.equal(availableSeats(12, 3, 4), 5);
assert.equal(availableSeats(12, 0, 12), 0);
assert.equal(availableSeats(12, 4, 10), 0);
for (const input of [[-1,0,0],[12,-1,0],[12,0,-1],[12.5,0,0],[12,NaN,0],[12,0,Infinity],[12,'1',0]]) {
  assert.throws(() => availableSeats(...input), RangeError);
}
console.log('CAPABILITY_FIXTURE_PASS: 10 independent behavioral assertions');
