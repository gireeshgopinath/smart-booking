function availableSeats(capacity, held, confirmed) {
  return capacity - confirmed;
}
module.exports = { availableSeats };
