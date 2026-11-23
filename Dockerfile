FROM nginx:alpine

ARG BUILD_NUMBER=dev
ARG GIT_SHA=local
ARG BUILD_DATE=unknown

COPY index.html /usr/share/nginx/html/index.html

RUN sed -i \
      -e "s/__BUILD__/${BUILD_NUMBER}/g" \
      -e "s/__SHA__/${GIT_SHA}/g" \
      -e "s/__DATE__/${BUILD_DATE}/g" \
      /usr/share/nginx/html/index.html

EXPOSE 80
