CREATE OR REPLACE MODEL ecommerce_prod.product_affinity OPTIONS (model_type='matrix_factorization',
                                                                 feedback_type='implicit',
                                                                 user_col='userId',
                                                                 item_col= 'product_recommended',
                                                                 rating_col='rating',
                                                                 l2_reg=30,
                                                                 num_factors=15) AS WITH UniqueUsersList AS
  (## GET ALL UNIQUE users SELECT distinct(userId)
   FROM `ecommerce_prod.events_flat_data`),
                                                                                         UserPurchaseEvents AS
  (## GET ALL purchase orders SELECT userId,
                                     items.productName
   FROM `ecommerce_prod.events_flat_data`,
        UNNEST(items) AS items
   WHERE event_name = 'purchase'
   GROUP BY 1,
            2),
                                                                                         ProductBoughtTogetherHistorically AS
  (## GET ALL items which ARE bought together SELECT userId AS prevUserId,
                                                     STRING_AGG(items.productName, ', ') AS productsBoughtTogether
   FROM `ecommerce_prod.events_flat_data`,
        UNNEST(items) AS items
   WHERE event_name = 'purchase'
     AND uniqueItemsQuantity > 1
   GROUP BY 1) ,
                                                                                         #select *
FROM ProductBoughtTogetherHistorically UserProductRecommendations AS
  (##
   FOR ALL items purchased BY USER in an
   ORDER PREPARE the list OF other items bought together SELECT userId,
                                                                cust_prev_purchase,
                                                                split(productsBoughtTogether, ',') AS product
   FROM
     (SELECT b.*,
             a.*
      FROM ProductBoughtTogetherHistorically a,

        (SELECT userId,
                productName AS cust_prev_purchase
         FROM UserPurchaseEvents
         WHERE userId in
             (SELECT userId
              FROM UniqueUsersList) ) b
      WHERE a.productsBoughtTogether like CONCAT('%', CAST(b.cust_prev_purchase AS STRING), '%') ## Compare EACH itemn in an
        ORDER WITH orders bought historically
        AND PREPARE a list OF items bought together
        AND userId != prevUSerId ## remove IF the product in an
        ORDER IS same AS the compared
        ORDER historically )),
     #select *
FROM UserProductRecommendations UserProductMatrix AS
  (SELECT UserProductRecommendations.userId,
          #cust_prev_purchase,
          product_recommended,
          ecommerce_prod.getratingbasedonProduct(TRIM(product_recommended)) AS rating
   FROM UserProductRecommendations
   CROSS JOIN UNNEST(UserProductRecommendations.product) AS product_recommended
   WHERE TRIM(product_recommended) <> TRIM(UserProductRecommendations.cust_prev_purchase) ### , remove IF the previous
     ORDER IS the same AS the CURRENT
     ORDER
   GROUP BY userId,
            product_recommended
   ORDER BY userId)
SELECT *
FROM UserProductMatrix l
WHERE NOT EXISTS
    (SELECT 1
     FROM UserPurchaseEvents
     WHERE userId = l.userId
       AND Trim(productName) = Trim(l.product_recommended)## CHECK IF an item in the recommendation list IS already bought BY the USER,
                                                                                                                                  IF so remove it )
ORDER BY userId