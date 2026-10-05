+{
    fn    => 'apply_twice',
    cases => [
        [ 'sample',   [ sub { $_[0] + 3 }, 10 ],   16 ],
        [ 'strings',  [ sub { $_[0] . '!' }, 'go' ], 'go!!' ],
        [ 'square',   [ sub { $_[0] * $_[0] }, 3 ], 81 ],
    ],
}
