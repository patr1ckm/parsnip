library(testthat)
library(parsnip)
library(rlang)
library(tibble)

# ------------------------------------------------------------------------------

context("multinom regression execution with glmnet")

ctrl <- fit_control(verbosity = 1, catch = FALSE)
caught_ctrl <- fit_control(verbosity = 1, catch = TRUE)
quiet_ctrl <- fit_control(verbosity = 0, catch = TRUE)

rows <- c(1, 51, 101)

# ------------------------------------------------------------------------------

test_that('glmnet execution', {

  skip_if_not_installed("glmnet")

  expect_error(
    res <- fit_xy(
      multinom_reg() %>% set_engine("glmnet"),
      control = ctrl,
      x = iris[, 1:4],
      y = iris$Species
    ),
    regexp = NA
  )

  expect_true(has_multi_predict(res))
  expect_equal(multi_predict_args(res), "penalty")

  expect_error(
    glmnet_xy_catch <- fit_xy(
      multinom_reg() %>% set_engine("glmnet"),
      x = iris[, 2:5],
      y = iris$Sepal.Length,
      control = caught_ctrl
    )
  )

})

test_that('glmnet prediction, one lambda', {

  skip_if_not_installed("glmnet")

  xy_fit <- fit_xy(
    multinom_reg(penalty = 0.1) %>% set_engine("glmnet"),
    control = ctrl,
    x = iris[, 1:4],
    y = iris$Species
  )

  uni_pred <-
    predict(xy_fit$fit,
            newx = as.matrix(iris[rows, 1:4]),
            s = xy_fit$spec$args$penalty, type = "class")
  uni_pred <- factor(uni_pred[,1], levels = levels(iris$Species))
  uni_pred <- unname(uni_pred)

  expect_equal(uni_pred, predict(xy_fit, iris[rows, 1:4], type = "class")$.pred_class)

  res_form <- fit(
    multinom_reg(penalty = 0.1) %>% set_engine("glmnet"),
    Species ~ log(Sepal.Width) + Petal.Width,
    data = iris,
    control = ctrl
  )

  form_mat <- model.matrix(Species ~ log(Sepal.Width) + Petal.Width, data = iris)
  form_mat <- form_mat[rows, -1]

  form_pred <-
    predict(res_form$fit,
            newx = form_mat,
            s = res_form$spec$args$penalty,
            type = "class")
  form_pred <- factor(form_pred[,1], levels = levels(iris$Species))
  expect_equal(form_pred, parsnip:::predict_class.model_fit(res_form, iris[rows, c("Sepal.Width", "Petal.Width")]))
  expect_equal(form_pred, predict(res_form, iris[rows, c("Sepal.Width", "Petal.Width")], type = "class")$.pred_class)

})


test_that('glmnet probabilities, mulitiple lambda', {

  skip_if_not_installed("glmnet")

  lams <- c(0.01, 0.1)

  xy_fit <- fit_xy(
    multinom_reg(penalty = lams) %>% set_engine("glmnet"),
    control = ctrl,
    x = iris[, 1:4],
    y = iris$Species
  )

  expect_error(predict(xy_fit, iris[rows, 1:4], type = "class"))
  expect_error(predict(xy_fit, iris[rows, 1:4], type = "prob"))

  mult_pred <-
    predict(xy_fit$fit,
            newx = as.matrix(iris[rows, 1:4]),
            s = lams, type = "response")
  mult_pred <- apply(mult_pred, 3, as_tibble)
  mult_pred <- dplyr:::bind_rows(mult_pred)
  mult_probs <- mult_pred
  names(mult_pred) <- paste0(".pred_", names(mult_pred))
  mult_pred$penalty <- rep(lams, each = 3)
  mult_pred$row <- rep(1:3, 2)
  mult_pred <- mult_pred[order(mult_pred$row, mult_pred$penalty),]
  mult_pred <- split(mult_pred[, -5], mult_pred$row)
  names(mult_pred) <- NULL
  mult_pred <- tibble(.pred = mult_pred)

  expect_equal(
    mult_pred$.pred,
    multi_predict(xy_fit, iris[rows, 1:4], penalty = lams, type = "prob")$.pred
  )

  mult_class <- names(mult_probs)[apply(mult_probs, 1, which.max)]
  mult_class <- tibble(
    .pred_class = mult_class,
    penalty = rep(lams, each = 3),
    row = rep(1:3, 2)
  )
  mult_class <- mult_class[order(mult_class$row, mult_class$penalty),]
  mult_class <- split(mult_class[, -3], mult_class$row)
  names(mult_class) <- NULL
  mult_class <- tibble(.pred = mult_class)

  expect_equal(
    mult_class$.pred,
    multi_predict(xy_fit, iris[rows, 1:4], penalty = lams)$.pred
  )

  expect_error(
    multi_predict(xy_fit, newdata = iris[rows, 1:4], penalty = lams),
    "Did you mean"
  )

  # Can predict probs with default penalty. See #108
  expect_error(
    multi_predict(xy_fit, new_data = iris[rows, 1:4], type = "prob"),
    NA
  )

})
