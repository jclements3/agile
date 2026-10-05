+{
    fn    => 'longest_after_replacements',
    cases => [
        [ 'sample',     [ 'ABAB', 2 ],      4 ],
        [ 'one change', [ 'AABABBA', 1 ],   4 ],
        [ 'empty',      [ '', 3 ],          0 ],
        [ 'no changes', [ 'AABBB', 0 ],     3 ],
        [ 'k too big',  [ 'ABC', 5 ],       3 ],
    ],
}
