+{
    fn    => 'clamp',
    cases => [
        [ 'sample',       [15],         10 ],
        [ 'below',        [-3],         0 ],
        [ 'given range',  [ 5, 0, 4 ],  4 ],
        [ 'inside',       [5],          5 ],
        [ 'hi of zero',   [ 5, -5, 0 ], 0 ],
        [ 'on the edge',  [ 10 ],       10 ],
    ],
}
