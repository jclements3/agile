+{
    fn    => 'sign',
    cases => [
        [ 'sample',            [-7],   -1 ],
        [ 'zero',              [0],    0 ],
        [ 'positive',          [3],    1 ],
        [ 'negative decimal',  [-0.5], -1 ],
        [ 'small positive',    [0.01], 1 ],
    ],
}
