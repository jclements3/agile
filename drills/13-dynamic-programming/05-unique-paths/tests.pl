+{
    fn    => 'unique_paths',
    cases => [
        [ 'sample',     [ 3, 3 ],   6 ],
        [ 'one row',    [ 1, 5 ],   1 ],
        [ 'one cell',   [ 1, 1 ],   1 ],
        [ 'three by 7', [ 3, 7 ],   28 ],
        [ 'larger',     [ 10, 10 ], 48620 ],
    ],
}
