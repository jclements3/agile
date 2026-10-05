+{
    fn    => 'least_interval',
    cases => [
        [ 'sample',        [ [qw(A A A B B B)], 2 ],            8 ],
        [ 'no cooldown',   [ [qw(A A A B B B)], 0 ],            6 ],
        [ 'all different', [ [qw(A B C D)], 3 ],                4 ],
        [ 'one letter',    [ [qw(A A A)], 2 ],                  7 ],
        [ 'enough others', [ [qw(A A A B C D E F G)], 2 ],      9 ],
        [ 'empty',         [ [], 2 ],                           0 ],
    ],
}
