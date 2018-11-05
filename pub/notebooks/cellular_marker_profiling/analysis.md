R Notebook
================

Cellular Marker Profiling
=========================

This notebook outlines the gating and visualization process for 4 experiments designed to test the ability of image cytometry to distinguish CD4+CD8- and CD4-CD8+ T cell population sizes in human samples (compared to flow cytometry).

``` r
library(tidyverse)
library(flowCore)
library(openCyto)
library(ggcyto)
```

Load FCS Data
-------------

Read in annotated FCS files exported from Cytokit as a single flowSet:

``` r
experiments <- c(
  '20180614_D22_RepA_Tcell_CD4-CD8-DAPI_5by5',
  '20180614_D22_RepB_Tcell_CD4-CD8-DAPI_5by5',
  '20180614_D23_RepA_Tcell_CD4-CD8-DAPI_5by5',
  '20180614_D23_RepB_Tcell_CD4-CD8-DAPI_5by5'
)
variants <- c(
  'v00', 'v01', 'v02', 'v03'
)

# Create data frame with metadata for each experimental replicate and variant in processing
gsm <- expand.grid(experiments, variants) %>% set_names(c('experiment', 'variant')) %>%
  mutate(path=str_glue('/lab/data/{experiment}/output/{variant}/cytometry/data.fcs')) %>%
  mutate(donor=str_extract(experiment, 'D\\d{2}')) %>%
  mutate(replicate=str_extract(experiment, 'Rep[A|B]')) %>%
  mutate(sample=str_glue('{donor}_{replicate}_{variant}')) %>%
  as('AnnotatedDataFrame')
sampleNames(gsm) <- gsm@data$sample


# Load FCS data and push spatial gating (as tiles) down to this level
load_fcs <- function(path, donor, replicate) {
  fr <- read.FCS(path)
  if (donor == 'D22' && replicate == 'RepB'){
    d <- exprs(fr)
    mask <- d[,'tilex'] < 4 | d[,'tiley'] > 2
    message(sprintf('Removing %s rows of %s for file %s\n', sum(!mask), nrow(fr), path))
    fr <- Subset(fr, mask)
  }
  if (donor == 'D23' && replicate == 'RepB'){
    d <- exprs(fr)
    mask <- (d[,'tilex'] != 1 | d[,'tiley'] != 1) & (d[,'tilex'] != 1 | d[,'tiley'] != 2)
    message(sprintf('Removing %s rows of %s for file %s\n', sum(!mask), nrow(fr), path))
    fr <- Subset(fr, mask)
  }
  fr
}

# Generate list of flowFrames named by sample
fsr <- gsm@data %>% select(path, donor, replicate) %>% 
  pmap(load_fcs) %>% set_names(gsm@data$sample)
```

    ## Removing 949 rows of 6631 for file /lab/data/20180614_D22_RepB_Tcell_CD4-CD8-DAPI_5by5/output/v00/cytometry/data.fcs

    ## Removing 939 rows of 7794 for file /lab/data/20180614_D23_RepB_Tcell_CD4-CD8-DAPI_5by5/output/v00/cytometry/data.fcs

    ## Removing 1219 rows of 8131 for file /lab/data/20180614_D22_RepB_Tcell_CD4-CD8-DAPI_5by5/output/v01/cytometry/data.fcs

    ## Removing 976 rows of 8606 for file /lab/data/20180614_D23_RepB_Tcell_CD4-CD8-DAPI_5by5/output/v01/cytometry/data.fcs

    ## Removing 950 rows of 6678 for file /lab/data/20180614_D22_RepB_Tcell_CD4-CD8-DAPI_5by5/output/v02/cytometry/data.fcs

    ## Removing 945 rows of 7801 for file /lab/data/20180614_D23_RepB_Tcell_CD4-CD8-DAPI_5by5/output/v02/cytometry/data.fcs

    ## Removing 1206 rows of 7992 for file /lab/data/20180614_D22_RepB_Tcell_CD4-CD8-DAPI_5by5/output/v03/cytometry/data.fcs

    ## Removing 982 rows of 8613 for file /lab/data/20180614_D23_RepB_Tcell_CD4-CD8-DAPI_5by5/output/v03/cytometry/data.fcs

``` r
# Create flowSet from list and attach phenoData
fsr <- flowSet(fsr)
sampleNames(fsr) <- gsm@data$sample
phenoData(fsr) <- gsm

fsr
```

    ## A flowSet with 16 experiments.
    ## 
    ##   column names:
    ##   regionindex tileindex tilex tiley rid rx ry id x y z cellsize celldiameter cellperimeter cellcircularity cellsolidity nucleussize nucleusdiameter nucleusperimeter nucleuscircularity nucleussolidity ciDAPI ciCD4 ciCD8 niDAPI niCD4 niCD8 cgnneighbors cgadjbgpct

Transformation and Gating
-------------------------

``` r
# Apply biexp transform to CD4 and CD8 signals
chnl <- c("ciCD4", "ciCD8")
trans <- transformList(chnl, biexponentialTransform())
fst <- transform(fsr, trans)

# Initialize a new gating set
gs <- GatingSet(fst)
```

    ## ................done!

``` r
markernames(gs) <- fsr@colnames %>% set_names(fsr@colnames)

# Apply static gates (determined in Explorer) on nuclear channel intensity, cell size/shape,
# and level of isolation (to ignore cells in large clumps)
add(gs, rectangleGate("ciDAPI"=c(50, 150), filterId='dapi'), parent='root')
```

    ## replicating filter 'dapi' across samples!

``` r
add(gs, rectangleGate("celldiameter"=c(3, 15), filterId='celldiameter'), parent='dapi')
```

    ## replicating filter 'celldiameter' across samples!

``` r
add(gs, rectangleGate("nucleusdiameter"=c(3, 15), filterId='nucleusdiameter'), parent='celldiameter')
```

    ## replicating filter 'nucleusdiameter' across samples!

``` r
add(gs, rectangleGate("cellcircularity"=c(80, Inf), filterId='cellcircularity'), parent='nucleusdiameter')
```

    ## replicating filter 'cellcircularity' across samples!

``` r
add(gs, rectangleGate("nucleuscircularity"=c(80, Inf), filterId='nucleuscircularity'), parent='cellcircularity')
```

    ## replicating filter 'nucleuscircularity' across samples!

``` r
add(gs, rectangleGate("cgnneighbors"=c(-Inf, 3.5), filterId='neighbors'), parent='nucleuscircularity')
```

    ## replicating filter 'neighbors' across samples!

``` r
# Apply dynamic gates for CD4/CD8, as determined by mindensity2
for (i in 1:length(gs)){
  gh <- gs[[i]]
  fr <- getData(gh)
  g1 <- mindensity2(fr, channel = 'ciCD4', filterId='CD4+', gate_range=c(3.5, 6))
  g2 <- mindensity2(fr, channel = 'ciCD8', filterId='CD8+', gate_range=c(4, 5.5))
  g <- quadGate(ciCD4=g1@min, ciCD8=g2@min)
  add(gh, g, parent='neighbors', names=c('CD4-CD8+', 'CD4+CD8+', 'CD4+CD8-', 'CD4-CD8-'))
}
recompute(gs)
```

    ## ................done!

``` r
# Plot the gating hierarchy
plot(gs)
```

![](analysis_files/figure-markdown_github/unnamed-chunk-4-1.png)

Merge Statistics w/ Flow Cytometry Results
------------------------------------------

``` r
# Extract long form population percentages/counts from gating set
df_ck <- getPopStats(gs, statistic='freq', format='long') %>%
  dplyr::filter(str_detect(Population, 'CD')) %>%
  mutate(raw_percent_ck=100*Count/ParentCount) %>%
  rename(population=Population, count=Count) %>%
  mutate(donor=str_extract(name, 'D\\d{2}')) %>%
  mutate(replicate=str_extract(name, 'Rep[A|B]')) %>%
  mutate(variant=str_extract(name, 'v\\d{2}$')) %>%
  select(sample=name, donor, population, replicate, variant, count, raw_percent_ck)
  
# Create data frame with population sizes from flow
df_flow <- tribble(
  ~donor, ~population, ~raw_percent_flow,
  'D22', 'CD4+CD8+', .68,
  'D22', 'CD4+CD8-', 75.8,
  'D22', 'CD4-CD8+', 17.5,
  'D22', 'CD4-CD8-', 6.01,
  'D23', 'CD4+CD8+', 2.03,
  'D23', 'CD4+CD8-', 54.1,
  'D23', 'CD4-CD8+', 33.3,
  'D23', 'CD4-CD8-', 10.5
) 

# Merge datasets together and ignore double negative group, as there was no
# CD3 expression signal to filter on in imaging
df_stats <- df_ck %>% inner_join(df_flow, by = c('donor', 'population')) %>%
  dplyr::filter(population != 'CD4-CD8-') %>%
  
  # Group by sample and compute population proportions renormalized 
  # after double negative omission
  group_by(sample) %>% mutate(
    norm_percent_flow=100*raw_percent_flow/sum(raw_percent_flow),
    norm_percent_ck=100*raw_percent_ck/sum(raw_percent_ck)
  ) %>% ungroup 

df_stats
```

    ## # A tibble: 48 x 10
    ##    sample donor population replicate variant count raw_percent_ck
    ##    <chr>  <chr> <chr>      <chr>     <chr>   <int>          <dbl>
    ##  1 D22_R… D22   CD4-CD8+   RepA      v00       348          11.6 
    ##  2 D22_R… D22   CD4+CD8+   RepA      v00        45           1.51
    ##  3 D22_R… D22   CD4+CD8-   RepA      v00      1884          63.0 
    ##  4 D22_R… D22   CD4-CD8+   RepB      v00       274           9.15
    ##  5 D22_R… D22   CD4+CD8+   RepB      v00       167           5.57
    ##  6 D22_R… D22   CD4+CD8-   RepB      v00      1962          65.5 
    ##  7 D23_R… D23   CD4-CD8+   RepA      v00       961          25.3 
    ##  8 D23_R… D23   CD4+CD8+   RepA      v00       136           3.58
    ##  9 D23_R… D23   CD4+CD8-   RepA      v00      1695          44.6 
    ## 10 D23_R… D23   CD4-CD8+   RepB      v00      1048          26.4 
    ## # ... with 38 more rows, and 3 more variables: raw_percent_flow <dbl>,
    ## #   norm_percent_flow <dbl>, norm_percent_ck <dbl>

``` r
# Determine correlation of expected vs actual percentages
df_stats_corr <- df_stats %>% group_by(variant) %>% 
  summarise(
    cor=cor(norm_percent_ck, norm_percent_flow), 
    p=cor.test(norm_percent_ck, norm_percent_flow)$p.value
  )

# Select best processing variant
variant_name <- df_stats_corr %>% arrange(p) %>% head(1) %>% .$variant
cat('Best variant: ', variant_name)
```

    ## Best variant:  v00

``` r
df_stats_corr
```

    ## # A tibble: 4 x 3
    ##   variant   cor        p
    ##   <chr>   <dbl>    <dbl>
    ## 1 v00     0.994 7.03e-11
    ## 2 v01     0.984 7.63e- 9
    ## 3 v02     0.992 3.24e-10
    ## 4 v03     0.989 1.35e- 9

Visualization
-------------

Show the CD4/CD8 scatterplots for each sample along with gate determined for each dimension:

``` r
get_density <- function(x, y){
  d <- densCols(x, y, colramp=colorRampPalette(c("black", "white")))
  as.numeric(col2rgb(d)[1,] + 1L)
}

extract_df <- function(i){
  gh <- gs[[i]]
  pd <- pData(gh)
  gates <- getGate(gh, 'CD4+CD8+')@min
  gs[[i]] %>% getData %>% exprs %>% as_tibble %>%
    mutate(
      sample=as.character(pd$sample), donor=pd$donor, 
      replicate=pd$replicate, variant=pd$variant,
      gCD4=gates['ciCD4'], gCD8=gates['ciCD8']
    ) %>% ungroup
}

df <- map(1:length(gs), extract_df) %>% bind_rows %>%
  group_by(sample) %>% mutate(density=get_density(ciCD4, ciCD8)) %>%
  dplyr::filter(variant==variant_name)

p_xy <- df %>%
  ggplot(aes(x=ciCD4, y=ciCD8)) + 
  geom_point(aes(color=density), size=.1, alpha=.5) + 
  scale_color_distiller(palette='Spectral', direction=-1) +
  geom_vline(data=df %>% group_by(sample) %>% summarize(v=gCD4[1]), aes(xintercept=v)) +
  geom_hline(data=df %>% group_by(sample) %>% summarize(v=gCD8[1]), aes(yintercept=v)) +
  facet_wrap(~sample, scales='free', nrow=2) + 
  guides(color=FALSE) +
  theme_bw() + theme(
    panel.grid.minor.x=element_blank(),
    panel.grid.minor.y=element_blank(),
    panel.grid.major.x=element_blank(),
    panel.grid.major.y=element_blank(),
    axis.ticks.x=element_blank(),
    axis.ticks.y=element_blank(),
    axis.text.x=element_blank(),
    axis.text.y=element_blank(),
    
    # Labels versions
    strip.background = element_rect(colour="white", fill="white")
    
    # Blank version
    # strip.text.x = element_blank()
  )
p_xy
```

![](analysis_files/figure-markdown_github/unnamed-chunk-7-1.png)

Plot the relative sizes of each cell population from both sources, and across both imaging replicates:

``` r
p_stat <- bind_rows(
    df_stats %>% dplyr::filter(variant==variant_name) %>%
      group_by(donor, population, replicate) %>% 
      summarise(percent=raw_percent_ck[1]) %>% ungroup %>%
      mutate(source='cytokit'),
    df_stats %>% dplyr::filter(variant==variant_name) %>% 
      group_by(donor, population) %>% 
      summarise(percent=raw_percent_flow[1]) %>% ungroup %>%
      mutate(source='flow', replicate='RepA')
  ) %>%
  mutate(source=str_glue('{source}-{replicate}')) %>%
  mutate(pct=str_glue('{p}%', p=round(percent, 0))) %>%
  ggplot(aes(x=source, y=percent, fill=population, label=pct)) +
  geom_bar(stat='identity', position='fill', color='white') +
  geom_text(size = 4, position=position_fill(vjust=.5)) +
  scale_fill_brewer(palette='Set1', guide=guide_legend(title='')) +
  scale_y_continuous(labels = scales::percent_format()) +
  facet_wrap(~donor) + 
  xlab('') + ylab('') +
  theme_bw() + theme(
    panel.grid.minor.x=element_blank(),
    panel.grid.minor.y=element_blank(),
    panel.grid.major.x=element_blank(),
    panel.grid.major.y=element_blank(),
    axis.ticks.x=element_blank(),
    axis.ticks.y=element_blank(),
    axis.text.y=element_blank(),
    strip.background = element_rect(colour="white", fill="white"),
    
    # Labeled version
    axis.text.x = element_text(angle = 90, hjust = 1)
    
    # Blank version
    # axis.text.x = element_blank(),
    # strip.text.x = element_blank()
  ) 
p_stat
```

![](analysis_files/figure-markdown_github/unnamed-chunk-8-1.png)

Side-by-side plot of the above (for annotation cleanup):

``` r
gridExtra::marrangeGrob(list(p_xy, p_stat), nrow=1, ncol=2)
```

![](analysis_files/figure-markdown_github/unnamed-chunk-9-1.png)