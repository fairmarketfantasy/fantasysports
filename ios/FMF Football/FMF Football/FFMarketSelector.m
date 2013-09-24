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
        
        _collectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(15, 0, frame.size.width-30, frame.size.height)
                                             collectionViewLayout:_flowLayout];
        _collectionView.delegate = self;
        _collectionView.dataSource = self;
        _collectionView.pagingEnabled = YES;
        _collectionView.backgroundColor = [UIColor redColor];
        _collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _collectionView.alwaysBounceHorizontal = YES;
        [_collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"MarketCell"];
        [self addSubview:_collectionView];
        
        UIButton *left = [UIButton buttonWithType:UIButtonTypeCustom];
        [left setTitle:@"<" forState:UIControlStateNormal];
        left.frame = CGRectMake(0, 0, 15, frame.size.height);
        left.autoresizingMask = UIViewAutoresizingNone;
        left.backgroundColor = [UIColor greenColor];
        [self addSubview:left];
        
        UIButton *right = [UIButton buttonWithType:UIButtonTypeCustom];
        [right setTitle:@">" forState:UIControlStateNormal];
        right.frame = CGRectMake(frame.size.width-15, 0, 15, frame.size.height);
        right.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        right.backgroundColor = [UIColor yellowColor];
        [self addSubview:right];
    }
    return self;
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
        [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:loc inSection:1]
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
    if (market.name && market.name.length) {
        marketLabel.text = market.name;
    } else {
        marketLabel.text = @"Unknown Market Name";
    }
    
    [cell.contentView addSubview:marketLabel];
    cell.backgroundColor = [UIColor blueColor];
    
    return cell;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end
