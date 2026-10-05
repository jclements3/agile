+{
    fn    => 'edit_distance',
    cases => [
        [ 'sample',        [ 'table', 'cable' ],     1 ],
        [ 'from empty',    [ '', 'abc' ],            3 ],
        [ 'to empty',      [ 'abc', '' ],            3 ],
        [ 'same',          [ 'same', 'same' ],       0 ],
        [ 'shift',         [ 'flaw', 'lawn' ],       2 ],
        [ 'classic',       [ 'kitten', 'sitting' ],  3 ],
        [ 'one letter',    [ 'a', 'b' ],             1 ],
    ],
}
