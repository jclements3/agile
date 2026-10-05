+{
    fn    => 'count_vowels',
    cases => [
        [ 'sample',     ['Programming'], 3 ],
        [ 'all upper',  ['AEIOU'],       5 ],
        [ 'none',       ['xyz'],         0 ],
        [ 'empty',      [''],            0 ],
        [ 'mixed',      ['Queue Up!'],   5 ],
    ],
}
