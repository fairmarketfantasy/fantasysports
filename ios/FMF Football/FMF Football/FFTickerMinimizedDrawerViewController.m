//
//  FFTickerMinimizedDrawerViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFTickerMinimizedDrawerViewController.h"

@interface FFTickerMinimizedDrawerViewController ()

@end

@implementation FFTickerMinimizedDrawerViewController

- (id)init
{
    self = [super init];
    if (self) {
        [self.collectionView registerClass:[UICollectionViewCell class]
                forCellWithReuseIdentifier:@"MinCell"];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (CGSize)collectionView:(UICollectionView*)collectionView
                    layout:(UICollectionViewLayout*)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath*)indexPath
{
    NSDictionary* player = [self.tickerData objectAtIndex:indexPath.row];

    NSString* nameValue = [NSString stringWithFormat:@"%@ (%@)", player[@"name"], player[@"position"]];
    CGFloat namw = [nameValue sizeWithFont:[FFStyle regularFont:14]
                         constrainedToSize:CGSizeMake(150, 100)].width;
    return CGSizeMake(56 + namw, 48);
}

- (UICollectionViewCell*)collectionView:(UICollectionView*)collectionView cellForItemAtIndexPath:(NSIndexPath*)indexPath
{
    UICollectionViewCell* cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"MinCell"
                                                                           forIndexPath:indexPath];

    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    NSDictionary* player = [self.tickerData objectAtIndex:indexPath.row];

    UIImageView* img = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
    img.contentMode = UIViewContentModeScaleAspectFit;
    [cell.contentView addSubview:img];
    [img setImageWithURL:[NSURL URLWithString:player[@"headshot_url"]]
        placeholderImage:[UIImage imageNamed:@"helmet-placeholder.png"]];

    UIImageView* overlay = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
    overlay.contentMode = UIViewContentModeScaleAspectFit;
    overlay.image = [UIImage imageNamed:@"player-cutout.png"];
    overlay.backgroundColor = [UIColor clearColor];
    [cell.contentView addSubview:overlay];

    NSString* nameValue = [NSString stringWithFormat:@"%@ (%@)", player[@"name"], player[@"position"]];
    CGFloat namw = [nameValue sizeWithFont:[FFStyle regularFont:14]
                         constrainedToSize:CGSizeMake(150, 100)].width;
    UILabel* nam = [[UILabel alloc] initWithFrame:CGRectMake(48, 15, namw, 15)];
    nam.font = [FFStyle regularFont:14];
    nam.textColor = [FFStyle white];
    nam.backgroundColor = [FFStyle darkGreen];
    nam.text = nameValue;
    [cell.contentView addSubview:nam];

    return cell;
}

@end
