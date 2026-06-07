FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
RUN apk add --no-cache nginx
COPY nginx.conf /etc/nginx/nginx.conf.template
EXPOSE 3000
CMD sh -c "sed 's/__PORT__/${PORT:-3000}/' /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf && nginx -g 'daemon off;'"
