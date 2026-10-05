+{
    fn    => 'fizzbuzz',
    cases => [
        [ 'sample', [5], [ 1, 2, 'Fizz', 4, 'Buzz' ] ],
        [ 'zero',   [0], [] ],
        [ 'one',    [1], [1] ],
        [ 'fifteen', [15], [ 1, 2, 'Fizz', 4, 'Buzz', 'Fizz', 7, 8, 'Fizz', 'Buzz', 11, 'Fizz', 13, 14, 'FizzBuzz' ] ],
    ],
}
