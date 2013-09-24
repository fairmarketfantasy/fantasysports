//
//  FFMarketSelector.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFMarketSelector.h"

@interface FFMarketSelector () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>

@property (nonatomic) UICollectionView *collectionView;
@property (nonatomic) UICollectionViewFlowLayout *flowLayout;

@end

@implementation FFMarketSelector

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _flowLayout = [[UICollectionViewFlowLayout alloc] init];
        _flowLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        _flowLayout.sectionInset = UIEdgeInsetsZero;
        _flowLayout.minimumInteritemSpacing = 0;
        _flowLayout.minimumLineSpacing = 0;
        
        _collectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(35, 0, frame.size.width-70, frame.size.height)
                                             collectionViewLayout:_flowLayout];
        _collectionView.delegate = self;
        _collectionView.dataSource = self;
        _collectionView.pagingEnabled = YES;
        _collectionView.backgroundColor = [FFStyle white];
        _collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _collectionView.alwaysBounceHorizontal = YES;
        _collectionView.showsHorizontalScrollIndicator = NO;
        [_collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"MarketCell"];
        [self addSubview:_collectionView];
        
        UIButton *left = [UIButton buttonWithType:UIButtonTypeCustom];
        [left setImage:[UIImage imageNamed:@"leftshuttle.png"] forState:UIControlStateNormal];
        left.frame = CGRectMake(0, 0, 35, frame.size.height);
        left.autoresizingMask = UIViewAutoresizingNone;
        [left addTarget:self action:@selector(left:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:left];
        
        UIButton *right = [UIButton buttonWithType:UIButtonTypeCustom];
        [right setImage:[UIImage imageNamed:@"rightshuttle.png"] forState:UIControlStateNormal];
        right.frame = CGRectMake(frame.size.width-35, 0, 35, frame.size.height);
        right.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [right addTarget:self action:@selector(right:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:right];
    }
    return self;
}

- (void)left:(UIButton *)sender
{
    NSArray *selected = [self.collectionView indexPathsForVisibleItems];
    if (selected && selected.count) {
        NSIndexPath *path = [selected objectAtIndex:0];
        if (path.item == 0) return; // already at the first item
        [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:path.item-1 inSection:0]
                                    atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                            animated:YES];
    }
}

- (void)right:(UIButton *)sender
{
    NSArray *selected = [self.collectionView indexPathsForVisibleItems];
    if (selected && selected.count) {
        NSIndexPath *path = [selected lastObject];
        if (path.item == (self.markets.count - 1)) return; // already at last item
        [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:path.item+1 inSection:0]
                                    atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                            animated:YES];
    }
}

- (void)setMarkets:(NSArray *)markets
{
    _markets = markets;
    [self.collectionView reloadData];
}

- (void)setSelectedMarket:(FFMarket *)selectedMarket
{
    _selectedMarket = selectedMarket;
    
    NSInteger loc = [_markets indexOfObject:selectedMarket];
    if (loc != NSNotFound) {
        [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:loc inSection:0]
                                    atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                            animated:YES];
    }
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [self.markets count];
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return CGSizeMake(self.collectionView.frame.size.width, self.collectionView.frame.size.height);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"MarketCell"
                                                                           forIndexPath:indexPath];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    FFMarket *market = self.markets[indexPath.item];
    
    UILabel *marketLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, cell.contentView.frame.size.width,
                                                                     cell.contentView.frame.size.height)];
    marketLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    marketLabel.font = [FFStyle regularFont:16];
    marketLabel.textColor = [FFStyle black];
    marketLabel.backgroundColor = [UIColor clearColor];
    marketLabel.textAlignment = NSTextAlignmentCenter;
    
    if (market.name && market.name.length) {
        marketLabel.text = market.name;
    } else {
        marketLabel.text = NSLocalizedString(@"Market", nil);
    }
    
    [cell.contentView addSubview:marketLabel];
//    cell.backgroundColor = [UIColor blueColor];
    
    return cell;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    NSArray *visible = [self.collectionView indexPathsForVisibleItems];
    if (visible && visible.count) {
        NSIndexPath *path = visible[0];
        if (self.delegate && [self.delegate respondsToSelector:@selector(didUpdateToNewMarket:)]) {
            [self.delegate didUpdateToNewMarket:self.markets[path.item]];
        }
    }
}

@end
