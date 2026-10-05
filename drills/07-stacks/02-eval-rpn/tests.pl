+{
    fn    => 'eval_rpn',
    cases => [
        [ 'sample',          [ [qw(3 4 + 2 *)] ],                 14 ],
        [ 'truncate',        [ [qw(7 -2 /)] ],                    -3 ],
        [ 'one number',      [ ['42'] ],                          42 ],
        [ 'operand order',   [ [qw(5 1 2 + 4 * -)] ],             -7 ],
        [ 'lesson',          [ [qw(2 3 + 4 *)] ],                 20 ],
        [ 'classic',         [ [qw(4 13 5 / +)] ],                6 ],
    ],
}
